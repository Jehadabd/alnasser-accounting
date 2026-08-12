// screens/add_transaction_screen.dart
// screens/add_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import 'package:intl/intl.dart'; // For currency formatting
import '../widgets/formatters.dart';
import 'dart:io';

import '../services/receipt_voucher_pdf_service.dart';
import '../models/customer_receipt_voucher.dart';
import '../services/printing_service.dart';
import '../services/database_service.dart';
// import '../services/drive_service.dart'; // Removed
import 'package:uuid/uuid.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import '../utils/money_calculator.dart'; // 🔒 إضافة MoneyCalculator للأمان المالي
import '../services/logo_service.dart'; // 🖼️ Custom logo loading

class AddTransactionScreen extends StatefulWidget {
  final Customer customer;

  const AddTransactionScreen({
    super.key,
    required this.customer,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isDebt = true; // true for adding debt, false for paying debt
  bool _isSaving = false; // 🔒 منع الضغط المزدوج على زر الحفظ


  @override
  @override
  void initState() {
    super.initState();
  }

  @override
  @override
  void dispose() {
    super.dispose();
  }

  // Helper to format currency with thousand separators (no decimals)
  String formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  Future<void> _saveTransaction() async {
    // 🔒 منع الضغط المزدوج - إذا كانت العملية جارية، لا تفعل شيئاً
    if (_isSaving) return;
    
    if (_formKey.currentState!.validate()) {
      // 🔒 تفعيل حالة الحفظ فوراً قبل أي عملية async
      setState(() => _isSaving = true);
      
      try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));
      final amountChanged = _isDebt ? amount : -amount;
      
      // ═══════════════════════════════════════════════════════════════════════════
      // 🔒 تحسين الأمان: استخدام MoneyCalculator لضمان دقة الحسابات
      // ═══════════════════════════════════════════════════════════════════════════
      final balanceBefore = widget.customer.currentTotalDebt;
      final newBalance = MoneyCalculator.add(balanceBefore, amountChanged);
      
      // 🔒 التحقق المزدوج من صحة الحساب
      final verification = MoneyCalculator.verifyTransaction(
        balanceBefore: balanceBefore,
        amountChanged: amountChanged,
        expectedBalanceAfter: newBalance,
      );
      
      if (!verification.isValid) {
        print('⚠️ تحذير أمني في المعاملة: ${verification.errorMessage}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الحساب: ${verification.errorMessage}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // 🔒 التحقق من أن التسديد لا يجعل الرصيد سالباً بشكل غير منطقي
      if (!_isDebt && newBalance < -0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: التسديد سيجعل الرصيد سالباً (${newBalance.toStringAsFixed(2)})'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final uuid = const Uuid().v4();
      final transaction = DebtTransaction(
        customerId: widget.customer.id!,
        amountChanged: amountChanged,
        balanceBeforeTransaction: balanceBefore, // تعيين الرصيد قبل المعاملة
        newBalanceAfterTransaction: newBalance,
        transactionNote:
            _noteController.text.isEmpty ? null : _noteController.text,
        transactionType:
            _isDebt ? 'manual_debt' : 'manual_payment', // Use specific types
        createdAt: DateTime.now(), // Add createdAt for consistency
        transactionDate: DateTime.now(), // Add transactionDate for consistency

        transactionUuid: uuid,
      );
      
      await context.read<AppProvider>().addTransaction(transaction);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'تم ${_isDebt ? 'إضافة' : 'تسديد'} مبلغ ${formatCurrency(amount)} دينار بنجاح!'),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
          ),
        );
        // --- هنا منطق سند القبض ---
        if (!_isDebt) {
          final shouldPrint = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('طباعة سند قبض'),
              content: const Text('هل تريد طباعة سند القبض لهذا التسديد؟'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('لا'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('نعم'),
                ),
              ],
            ),
          );
          if (shouldPrint == true) {
            // الحصول على رقم سند القبض التالي
            final db = DatabaseService();
            final receiptNumber = await db.getNextCustomerReceiptNumber();
            
            final font = pw.Font.ttf(
                await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
            // استخدام نفس خط الفاتورة لكلمة الناصر
            final alnaserFont = pw.Font.ttf(await rootBundle
                .load('assets/fonts/PTBLDHAD.TTF'));
            // تحميل اللوجو باستخدام خدمة اللوجو
            final logoImage = await LogoService.getLogoImage();
            final pdf =
                await ReceiptVoucherPdfService.generateReceiptVoucherPdf(
              customerName: widget.customer.name,
              beforePayment: balanceBefore,
              paidAmount: amount,
              afterPayment: newBalance,
              dateTime: DateTime.now(),
              font: font,
              alnaserFont: alnaserFont,
              logoImage: logoImage,
              receiptNumber: receiptNumber,
            );
            
            // حفظ سند القبض في قاعدة البيانات
            final receipt = CustomerReceiptVoucher(
              receiptNumber: receiptNumber,
              customerId: widget.customer.id!,
              customerName: widget.customer.name,
              beforePayment: balanceBefore,
              paidAmount: amount,
              afterPayment: newBalance,
              createdAt: DateTime.now(),
            );
            await db.insertCustomerReceiptVoucher(receipt);
            
            // حفظ PDF في ملف مؤقت وفتحه في Microsoft Edge
            final tempDir = Directory.systemTemp;
            final filePath =
                '${tempDir.path}/receipt_voucher_${DateTime.now().millisecondsSinceEpoch}.pdf';
            final file = File(filePath);
            await file.writeAsBytes(await pdf.save());
            await Process.start('cmd', ['/c', 'start', 'msedge', filePath]);
          }
        }
        Navigator.pop(context);
      }
      } catch (e) {
        // 🔒 في حالة حدوث خطأ، نعيد تفعيل الزر
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء الحفظ: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        // 🔒 إعادة تفعيل الزر في جميع الحالات
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('الرجاء تصحيح الأخطاء في النموذج قبل الحفظ.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }



  @override
  Widget build(BuildContext context) {
    // Define the consistent theme colors for the screen
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo 700
    final Color accentColor =
        const Color(0xFF8C9EFF); // Light Indigo Accent (Indigo A200)
    final Color textColor =
        const Color(0xFF212121); // Dark grey for general text
    final Color lightBackgroundColor =
        const Color(0xFFF8F8F8); // Very light grey for text field fill
    final Color successColor =
        Colors.green[600]!; // Green for success messages/positive debt
    final Color errorColor =
        Colors.red[700]!; // Red for error messages/negative debt

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
          titleLarge: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              color: Colors.white), // AppBar title
          titleMedium: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: textColor), // Section titles
          bodyLarge:
              TextStyle(fontSize: 16.0, color: textColor), // General body text
          bodyMedium:
              TextStyle(fontSize: 14.0, color: textColor), // Smaller body text
          labelLarge: TextStyle(
              fontSize: 16.0,
              color: Colors.white,
              fontWeight: FontWeight.w600), // Button text
          labelMedium: TextStyle(
              fontSize: 14.0, color: Colors.grey[600]), // Input field labels
          bodySmall: TextStyle(
              fontSize: 12.0, color: Colors.grey[700]), // Hint text / captions
        ),
        // Define input field decoration theme
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            // Default border style
            borderRadius: BorderRadius.circular(10.0), // Rounded corners
            borderSide:
                BorderSide(color: Colors.grey[400]!), // Light grey border
          ),
          enabledBorder: OutlineInputBorder(
            // Border when enabled and not focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            // Border when focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: primaryColor, width: 2.0), // Primary color, thicker
          ),
          errorBorder: OutlineInputBorder(
            // Border when in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: errorColor, width: 2.0), // Error color, thicker
          ),
          focusedErrorBorder: OutlineInputBorder(
            // Border when focused and in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          labelStyle: TextStyle(
              color: Colors.grey[700], fontSize: 15.0), // Label text style
          hintStyle: TextStyle(
              color: Colors.grey[500], fontSize: 14.0), // Hint text style
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16.0, horizontal: 16.0), // Inner padding
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
            padding: const EdgeInsets.symmetric(
                vertical: 16.0, horizontal: 20.0), // Inner padding
            elevation: 4, // Shadow elevation
            textStyle: TextStyle(
                fontSize: 18.0, fontWeight: FontWeight.bold), // Text style
          ),
        ),
        // Define AppBar theme
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor, // AppBar background color
          foregroundColor: Colors.white, // AppBar text/icon color
          centerTitle: true, // Center title
          elevation: 4, // Shadow elevation
          titleTextStyle: TextStyle(
            // Title text style (inherits from TextTheme.titleLarge)
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        // Define Card theme
        cardTheme: CardThemeData(
          elevation: 3, // Consistent shadow for cards
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(12.0), // Rounded corners for cards
          ),
          margin: EdgeInsets
              .zero, // Reset default card margin to manage it manually
        ),
        // Define ListTile theme
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: Colors.transparent, // Default transparent
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        // Define TextButton theme (if any are used in future updates)
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        // Define IconButton theme (if any are used in future updates)
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
        // SegmentedButton specific styling
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: SegmentedButton.styleFrom(
            foregroundColor: primaryColor, // Unselected text/icon color
            selectedForegroundColor: Colors.white, // Selected text/icon color
            selectedBackgroundColor: primaryColor, // Selected background color
            backgroundColor:
                lightBackgroundColor, // Unselected background color
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
              side: BorderSide(
                  color: primaryColor, width: 1.0), // Border color for segments
            ),
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w500),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إضافة معاملة'),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(
                24.0), // Consistent padding for the entire view
            children: [
              Card(
                margin: const EdgeInsets.only(
                    bottom: 24.0), // Margin below the card
                child: Padding(
                  padding:
                      const EdgeInsets.all(20.0), // Increased internal padding
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'معلومات العميل',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary, // Primary color for heading
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 20.0), // Increased spacing
                      _buildInfoRow('الاسم', widget.customer.name, context),
                      const SizedBox(height: 12.0), // Increased spacing
                      _buildInfoRow(
                        'الدين الحالي',
                        '${formatCurrency(widget.customer.currentTotalDebt)} دينار', // Formatted currency
                        context,
                        valueColor: widget.customer.currentTotalDebt > 0
                            ? Theme.of(context)
                                .colorScheme
                                .error // Red for debt
                            : Theme.of(context)
                                .colorScheme
                                .tertiary, // Green for no debt
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12.0), // Spacing before segmented button
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('إضافة دين'),
                    icon:
                        Icon(Icons.add_circle_outline, size: 28), // Themed icon
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('تسديد دين'),
                    icon: Icon(Icons.remove_circle_outline,
                        size: 28), // Themed icon
                  ),
                ],
                selected: {_isDebt},
                onSelectionChanged: (Set<bool> newSelection) {
                  setState(() {
                    _isDebt = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 20.0), // Increased spacing
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'المبلغ',
                  hintText: 'أدخل المبلغ',
                  suffixText: ' دينار', // Added space for better readability
                  prefixIcon: Icon(Icons.attach_money,
                      color:
                          Theme.of(context).colorScheme.primary), // Themed icon
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  ThousandSeparatorInputFormatter(),
                  LengthLimitingTextInputFormatter(15),
                ],
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'الرجاء إدخال المبلغ';
                  }
                  final number = double.tryParse(value.replaceAll(',', ''));
                  if (number == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  if (number <= 0) {
                    return 'يجب أن يكون المبلغ أكبر من صفر';
                  }
                  if (number > 1000000000) {
                    // Preserving original functional constraint
                    return 'المبلغ أكبر من الحد المسموح به';
                  }
                  if (!_isDebt && number > widget.customer.currentTotalDebt) {
                    // Preserving original functional constraint
                    return 'المبلغ المدخل أكبر من الدين الحالي';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              // معاينة الرصيد بعد الحفظ
              Builder(builder: (ctx) {
                final entered = double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
                final signed = _isDebt ? entered : -entered;
                // 🔒 استخدام MoneyCalculator للمعاينة أيضاً
                final newBalance = MoneyCalculator.add(widget.customer.currentTotalDebt, signed);
                final color = newBalance > widget.customer.currentTotalDebt
                    ? Theme.of(ctx).colorScheme.error
                    : Theme.of(ctx).colorScheme.tertiary;
                return Card(
                  elevation: 0,
                  color: Theme.of(ctx).colorScheme.surfaceVariant,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('المعاينة', style: Theme.of(ctx).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('الرصيد الحالي', style: Theme.of(ctx).textTheme.bodyMedium),
                            Text(formatCurrency(widget.customer.currentTotalDebt), style: Theme.of(ctx).textTheme.bodyMedium),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_isDebt ? 'إضافة' : 'تسديد', style: Theme.of(ctx).textTheme.bodyMedium),
                            Text(formatCurrency(signed.abs()), style: Theme.of(ctx).textTheme.bodyMedium),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('الرصيد الجديد بعد الحفظ', style: Theme.of(ctx).textTheme.bodyLarge),
                            Text(
                              formatCurrency(newBalance),
                              style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(color: color, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20.0), // Increased spacing
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: 'ملاحظات',
                  hintText: 'أدخل ملاحظات إضافية (اختياري)',
                  prefixIcon: Icon(Icons.notes_outlined,
                      color: Theme.of(context).colorScheme.primary),

                ),
                maxLines: 3,
              ),

              const SizedBox(height: 32.0), // Increased spacing before button
              ElevatedButton.icon(
                // 🔒 تعطيل الزر أثناء عملية الحفظ
                onPressed: _isSaving ? null : _saveTransaction,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_isDebt
                        ? Icons.add_task
                        : Icons.check_circle_outline),
                label: Text(_isSaving
                    ? 'جاري الحفظ...'
                    : (_isDebt ? 'إضافة دين' : 'تسديد دين')),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity,
                      56), // Larger button for better tap target
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Modified to take BuildContext for theme access and ensure consistent text styles
  Widget _buildInfoRow(String label, String value, BuildContext context,
      {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
