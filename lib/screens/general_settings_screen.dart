import 'dart:io';
import 'package:flutter/material.dart';

import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/printing_service.dart';
import 'package:alnaser/services/printing_service_platform_io.dart';
import 'package:alnaser/services/thermal_receipt_service.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intl/intl.dart';

import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';
import '../services/password_service.dart';
import '../services/pdf_service.dart';
import '../services/invoice_settings_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'alert_settings_screen.dart'; // 🔔
import 'invoice_design_screen.dart'; // 🧳 تصميم الفاتورة
import 'telegram_settings_screen.dart'; // 📤 إعدادات تيليغرام
import 'discord_settings_screen.dart'; // 💬 إعدادات Discord
import 'dropbox_backup_screen.dart'; // ☁️ النسخ الاحتياطي السحابي
import 'firebase_sync_settings_screen.dart';
import 'firebase_custom_setup_screen.dart';

import '../models/account_statement_item.dart';
import '../models/verification_result.dart'; // ✅ Added
import '../services/smart_search/smart_search.dart' as smart_search; // 🧠 البحث الذكي


class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  late AppSettings _appSettings;
  final List<TextEditingController> _phoneNumberControllers = [];
  final TextEditingController _companyDescriptionController = TextEditingController();
  
  // ألوان العناصر المختلفة
  Color _remainingAmountColor = Colors.black;
  Color _discountColor = Colors.black;
  Color _loadingFeesColor = Colors.black;
  Color _totalBeforeDiscountColor = Colors.black;
  Color _totalAfterDiscountColor = Colors.black;
  Color _previousDebtColor = Colors.black;
  Color _currentDebtColor = Colors.black;
  Color _electricPhoneColor = Colors.black;
  Color _healthPhoneColor = Colors.black;
  Color _companyDescriptionColor = Colors.black;
  Color _companyNameColor = Colors.green;
  Color _itemSerialColor = Colors.black;
  Color _itemDetailsColor = Colors.black;
  Color _itemQuantityColor = Colors.black;
  Color _itemPriceColor = Colors.black;
  Color _itemTotalColor = Colors.black;
  Color _noticeColor = Colors.red;
  Color _paidAmountColor = Colors.black;
  
  // إعدادات نقاط المؤسسين

  // 💰 إعدادات الأرباح
  final TextEditingController _adHocProfitController = TextEditingController();
  final TextEditingController _manualDebtProfitController = TextEditingController();
  
  // إعدادات الفاتورة والتسعير
  bool _autoScrollInvoice = true;
  bool _allowNegativeStock = false;
  String _costingMethod = 'last_purchase'; // طريقة حساب التكلفة
  int _pricingMode = 99; // وضع التسعير الافتراضي
  final TextEditingController _wholesaleCustomerLimitController = TextEditingController();
  
  // 📱 رقم الجهاز للفواتير
  int _invoiceDeviceId = 1;
  final TextEditingController _invoiceDeviceController = TextEditingController();

  
  // 📱 قسم المحل
  String _storeSection = 'كهربائيات';
  
  // 🏪 اسم الفرع
  String _branchName = 'الفرع الرئيسي';
  
  // 🔐 خدمة كلمة السر
  final PasswordService _passwordService = PasswordService();
  
  // 🖨️ إعدادات الطابعات
  List<PrinterDevice> _availablePrinters = [];
  PrinterDevice? _posThermalPrinter;
  PrinterDevice? _invoicePrinter;
  bool _loadingPrinters = false;


  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _appSettings = await SettingsManager.getAppSettings();
    
    // تحميل الألوان
    _remainingAmountColor = Color(_appSettings.remainingAmountColor);
    _discountColor = Color(_appSettings.discountColor);
    _loadingFeesColor = Color(_appSettings.loadingFeesColor);
    _totalBeforeDiscountColor = Color(_appSettings.totalBeforeDiscountColor);
    _totalAfterDiscountColor = Color(_appSettings.totalAfterDiscountColor);
    _previousDebtColor = Color(_appSettings.previousDebtColor);
    _currentDebtColor = Color(_appSettings.currentDebtColor);
    _electricPhoneColor = Color(_appSettings.electricPhoneColor);
    _healthPhoneColor = Color(_appSettings.healthPhoneColor);
    _companyDescriptionColor = Color(_appSettings.companyDescriptionColor);
    _companyNameColor = Color(_appSettings.companyNameColor);
    _itemSerialColor = Color(_appSettings.itemSerialColor);
    _itemDetailsColor = Color(_appSettings.itemDetailsColor);
    _itemQuantityColor = Color(_appSettings.itemQuantityColor);
    _itemPriceColor = Color(_appSettings.itemPriceColor);
    _itemTotalColor = Color(_appSettings.itemTotalColor);
    _noticeColor = Color(_appSettings.noticeColor);
    _paidAmountColor = Color(_appSettings.paidAmountColor);
    

    // تحميل إعدادات الأرباح
    _adHocProfitController.text = _appSettings.defaultAdHocProfitPercentage.toString();
    _manualDebtProfitController.text = _appSettings.manualDebtProfitPercentage.toString();
    
    // تحميل إعدادات الفاتورة والتسعير
    _autoScrollInvoice = _appSettings.autoScrollInvoice;
    _allowNegativeStock = _appSettings.allowNegativeStock;
    _costingMethod = _appSettings.costingMethod;
    _pricingMode = _appSettings.pricingMode;
    _wholesaleCustomerLimitController.text = _appSettings.wholesaleCustomerLimit.toString();
    
    // تحميل رقم الجهاز للفواتير
    _invoiceDeviceId = await InvoiceSettingsService.getInvoiceDeviceId();
    _invoiceDeviceController.text = _invoiceDeviceId.toString();
    // تحميل قسم المحل
    _storeSection = _appSettings.storeSection;
    
    // تحميل اسم الفرع
    _branchName = _appSettings.branchName;
    
    // تحميل وصف الشركة
    _companyDescriptionController.text = _appSettings.companyDescription;
    
    // تحميل أرقام الهواتف
    _phoneNumberControllers.clear();
    for (var number in _appSettings.phoneNumbers) {
      _phoneNumberControllers.add(TextEditingController(text: number));
    }
    if (_phoneNumberControllers.isEmpty) {
      _phoneNumberControllers.add(TextEditingController());
    }
    
    // 🖨️ تحميل إعدادات الطابعات
    _loadPrinters();
    
    setState(() {});
  }
  
  /// تحميل الطابعات المتاحة من النظام
  Future<void> _loadPrinters() async {
    setState(() => _loadingPrinters = true);
    try {
      final printingService = getPlatformPrintingService();
      _availablePrinters = await printingService.findSystemPrinters();
      _posThermalPrinter = await SettingsManager.getPosThermalPrinter();
      _invoicePrinter = await SettingsManager.getInvoicePrinter();
    } catch (e) {
      print('خطأ في تحميل الطابعات: $e');
    }
    if (mounted) {
      setState(() => _loadingPrinters = false);
    }
  }
  
  /// اختيار طابعة الكاشير الحرارية
  Future<void> _selectPosThermalPrinter(PrinterDevice? printer) async {
    if (printer != null) {
      await SettingsManager.savePosThermalPrinter(printer);
      setState(() => _posThermalPrinter = printer);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديد طابعة الكاشير: ${printer.name}')),
        );
      }
    }
  }
  
  /// اختيار طابعة الفواتير
  Future<void> _selectInvoicePrinter(PrinterDevice? printer) async {
    if (printer != null) {
      await SettingsManager.saveInvoicePrinter(printer);
      setState(() => _invoicePrinter = printer);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديد طابعة الفواتير: ${printer.name}')),
        );
      }
    }
  }
  
  /// تجربة طباعة إيصال حراري
  Future<void> _testThermalPrint() async {
    if (_posThermalPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار طابعة الكاشير أولاً'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    final success = await ThermalReceiptService().printTestReceipt();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '✓ تم طباعة إيصال تجريبي' : '✗ فشل في الطباعة'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _saveSettings() async {
    final newPhoneNumbers = _phoneNumberControllers
        .map((controller) => controller.text)
        .where((text) => text.isNotEmpty)
        .toList();

    _appSettings = _appSettings.copyWith(
      phoneNumbers: newPhoneNumbers,
      remainingAmountColor: _remainingAmountColor.value,
      discountColor: _discountColor.value,
      loadingFeesColor: _loadingFeesColor.value,
      totalBeforeDiscountColor: _totalBeforeDiscountColor.value,
      totalAfterDiscountColor: _totalAfterDiscountColor.value,
      previousDebtColor: _previousDebtColor.value,
      currentDebtColor: _currentDebtColor.value,
      electricPhoneColor: _electricPhoneColor.value,
      healthPhoneColor: _healthPhoneColor.value,
      companyDescriptionColor: _companyDescriptionColor.value,
      companyDescription: _companyDescriptionController.text,
      companyNameColor: _companyNameColor.value,
      itemSerialColor: _itemSerialColor.value,
      itemDetailsColor: _itemDetailsColor.value,
      itemQuantityColor: _itemQuantityColor.value,
      itemPriceColor: _itemPriceColor.value,
      itemTotalColor: _itemTotalColor.value,
      noticeColor: _noticeColor.value,
      paidAmountColor: _paidAmountColor.value,

      defaultAdHocProfitPercentage: double.tryParse(_adHocProfitController.text) ?? 10.0,
      manualDebtProfitPercentage: double.tryParse(_manualDebtProfitController.text) ?? 15.0,
      autoScrollInvoice: _autoScrollInvoice,
      allowNegativeStock: _allowNegativeStock,
      costingMethod: _costingMethod,
      pricingMode: _pricingMode,
      wholesaleCustomerLimit: double.tryParse(_wholesaleCustomerLimitController.text) ?? 5000000.0,

      storeSection: _storeSection,
      branchName: _branchName,
    );
    await SettingsManager.saveAppSettings(_appSettings);
    
    // حفظ رقم الجهاز
    final parsedDeviceId = int.tryParse(_invoiceDeviceController.text.trim());
    if (parsedDeviceId != null) {
      await InvoiceSettingsService.setInvoiceDeviceId(parsedDeviceId);
      _invoiceDeviceId = parsedDeviceId;
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات بنجاح')),
      );
    }
  }

  void _addPhoneNumberField() {
    setState(() {
      _phoneNumberControllers.add(TextEditingController());
    });
  }

  void _removePhoneNumberField(int index) {
    setState(() {
      _phoneNumberControllers[index].dispose();
      _phoneNumberControllers.removeAt(index);
    });
  }

  void _pickColor(String colorType) {
    Color currentColor;
    switch (colorType) {
      case 'remainingAmount':
        currentColor = _remainingAmountColor;
        break;
      case 'discount':
        currentColor = _discountColor;
        break;
      case 'loadingFees':
        currentColor = _loadingFeesColor;
        break;
      case 'totalBeforeDiscount':
        currentColor = _totalBeforeDiscountColor;
        break;
      case 'totalAfterDiscount':
        currentColor = _totalAfterDiscountColor;
        break;
      case 'previousDebt':
        currentColor = _previousDebtColor;
        break;
      case 'currentDebt':
        currentColor = _currentDebtColor;
        break;
      case 'electricPhone':
        currentColor = _electricPhoneColor;
        break;
      case 'healthPhone':
        currentColor = _healthPhoneColor;
        break;
      case 'companyDescription':
        currentColor = _companyDescriptionColor;
        break;
      case 'companyName':
        currentColor = _companyNameColor;
        break;
      case 'itemSerial':
        currentColor = _itemSerialColor;
        break;
      case 'itemDetails':
        currentColor = _itemDetailsColor;
        break;
      case 'itemQuantity':
        currentColor = _itemQuantityColor;
        break;
      case 'itemPrice':
        currentColor = _itemPriceColor;
        break;
      case 'itemTotal':
        currentColor = _itemTotalColor;
        break;
      case 'notice':
        currentColor = _noticeColor;
        break;
      case 'paidAmount':
        currentColor = _paidAmountColor;
        break;
      default:
        currentColor = Colors.black;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        Color tempColor = currentColor;
        return AlertDialog(
          title: Text('اختر لون $colorType'),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: currentColor,
              onColorChanged: (color) {
                tempColor = color;
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('إلغاء'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('حفظ'),
              onPressed: () {
                setState(() {
                  switch (colorType) {
                    case 'remainingAmount':
                      _remainingAmountColor = tempColor;
                      break;
                    case 'discount':
                      _discountColor = tempColor;
                      break;
                    case 'loadingFees':
                      _loadingFeesColor = tempColor;
                      break;
                    case 'totalBeforeDiscount':
                      _totalBeforeDiscountColor = tempColor;
                      break;
                    case 'totalAfterDiscount':
                      _totalAfterDiscountColor = tempColor;
                      break;
                    case 'previousDebt':
                      _previousDebtColor = tempColor;
                      break;
                    case 'currentDebt':
                      _currentDebtColor = tempColor;
                      break;
                    case 'electricPhone':
                      _electricPhoneColor = tempColor;
                      break;
                    case 'healthPhone':
                      _healthPhoneColor = tempColor;
                      break;
                    case 'companyDescription':
                      _companyDescriptionColor = tempColor;
                      break;
                    case 'companyName':
                      _companyNameColor = tempColor;
                      break;
                    case 'itemSerial':
                      _itemSerialColor = tempColor;
                      break;
                    case 'itemDetails':
                      _itemDetailsColor = tempColor;
                      break;
                    case 'itemQuantity':
                      _itemQuantityColor = tempColor;
                      break;
                    case 'itemPrice':
                      _itemPriceColor = tempColor;
                      break;
                    case 'itemTotal':
                      _itemTotalColor = tempColor;
                      break;
                    case 'notice':
                      _noticeColor = tempColor;
                      break;
                    case 'paidAmount':
                      _paidAmountColor = tempColor;
                      break;
                  }
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    for (var controller in _phoneNumberControllers) {
      controller.dispose();
    }
    _companyDescriptionController.dispose();

    _adHocProfitController.dispose();
    _manualDebtProfitController.dispose();
    _wholesaleCustomerLimitController.dispose();
    super.dispose();
  }

  /// دالة لعرض حوار تأكيد محمي بكلمة سر
  Future<bool> _showProtectedChangeDialog({
    required String title,
    required String message,
  }) async {
    // أولاً: عرض رسالة التحذير
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('متابعة', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return false;
    
    // ثانياً: طلب كلمة السر
    final passwordController = TextEditingController();
    final passwordConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock, color: Colors.deepPurple, size: 28),
            SizedBox(width: 8),
            Text('أدخل كلمة السر', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'كلمة السر',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.lock_outline),
          ),
          onSubmitted: (value) async {
            final isCorrect = await _passwordService.verifyPassword(value);
            Navigator.of(context).pop(isCorrect);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final isCorrect = await _passwordService.verifyPassword(passwordController.text);
              Navigator.of(context).pop(isCorrect);
            },
            child: const Text('تأكيد', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    
    if (passwordConfirmed != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('كلمة السر غير صحيحة'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
    
    return true;
  }

  static const Color primaryColor = Color(0xFF3F51B5);

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
      onTap: onTap,
    );
  }

  Widget _buildColorTile(String title, Color color, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildModernPrinterSelector({
    required String title,
    required IconData icon,
    required PrinterDevice? selectedPrinter,
    required List<PrinterDevice> printers,
    required Function(PrinterDevice) onSelected,
    required Color color,
  }) {
    final isSelected = selectedPrinter != null;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? color.withOpacity(0.5) : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.grey[300],
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          selectedPrinter?.name ?? 'لم يتم تحديد طابعة',
          style: TextStyle(
            color: isSelected ? Colors.black87 : Colors.grey,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        trailing: PopupMenuButton<PrinterDevice>(
          onSelected: onSelected,
          itemBuilder: (context) {
            return printers.map((p) => PopupMenuItem(
              value: p,
              child: Row(
                children: [
                  Icon(Icons.print, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(p.name),
                  if (selectedPrinter?.name == p.name) ...[
                    const Spacer(),
                    Icon(Icons.check, color: color, size: 16),
                  ]
                ],
              ),
            )).toList();
          },
          child: Chip(
            label: const Text('تغيير', style: TextStyle(fontSize: 12)),
            avatar: const Icon(Icons.edit, size: 14),
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات العامة'),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'حفظ الإعدادات',
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          
          // 👤 قسم إدارة المستخدمين
          _buildSettingsCard(
            icon: Icons.admin_panel_settings,
            iconColor: Colors.deepPurple,
            title: 'إدارة المستخدمين والصلاحيات',
            child: _buildActionTile(
              icon: Icons.people,
              iconColor: Colors.deepPurple,
              title: 'المستخدمين والمحاسبين',
              subtitle: 'إضافة Admin، إضافة محاسبين، تحديد الصلاحيات',
              onTap: () {
                Navigator.pushNamed(context, '/user_management');
              },
            ),
          ),

          // 🖨️ إعدادات الطابعات
          _buildSettingsCard(
            icon: Icons.print,
            iconColor: Colors.teal,
            title: 'إعدادات الطابعات',
            child: Column(
              children: [
                if (_loadingPrinters)
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_availablePrinters.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            Platform.isAndroid || Platform.isIOS
                                ? 'لم يتم العثور على طابعات. سيتم استخدام نظام الطباعة الافتراضي للهاتف.'
                                : 'لم يتم العثور على طابعات في النظام. يرجى التحقق من تعريف الطابعات في الويندوز.',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  // 1. طابعة الكاشير
                  _buildModernPrinterSelector(
                    title: 'طابعة الكاشير (Receipts)',
                    icon: Icons.receipt,
                    selectedPrinter: _posThermalPrinter,
                    printers: _availablePrinters,
                    onSelected: (p) => _selectPosThermalPrinter(p),
                    color: Colors.teal,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 2. طابعة الفواتير
                  _buildModernPrinterSelector(
                    title: 'طابعة الفواتير (A4)',
                    icon: Icons.description,
                    selectedPrinter: _invoicePrinter,
                    printers: _availablePrinters,
                    onSelected: (p) => _selectInvoicePrinter(p),
                    color: Colors.indigo,
                  ),

                  const SizedBox(height: 24),
                  
                  // Test Button
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton.icon(
                      onPressed: _testThermalPrint,
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('💡 تجربة طباعة إيصال'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _loadPrinters,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحديث القائمة'),
                ),
              ],
            ),
          ),

          // �🔔 قسم التنبيهات
          _buildSettingsCard(
            icon: Icons.notifications_active,
            iconColor: Colors.orange,
            title: 'إعدادات التنبيهات',
            child: _buildActionTile(
              icon: Icons.notifications,
              iconColor: Colors.orange,
              title: 'تنبيهات المخزون والركود',
              subtitle: 'تحديد متى تظهر تنبيهات نقص المخزون والمواد الراكدة',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AlertSettingsScreen()),
                ).then((_) => _loadSettings());
              },
            ),
          ),
          
          // 🧾 تصميم الفاتورة
          _buildSettingsCard(
            icon: Icons.receipt_long,
            iconColor: Colors.indigo,
            title: 'تصميم الفاتورة',
            child: _buildActionTile(
              icon: Icons.design_services,
              iconColor: Colors.indigo,
              title: 'تخصيص الفاتورة',
              subtitle: 'تعديل أعمدة الجدول، اللوجو، اسم الشركة، العنوان، وأرقام الهاتف',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const InvoiceDesignScreen()),
                ).then((_) => _loadSettings());
              },
            ),
          ),

          // 🔥 إعدادات مزامنة Firebase
          _buildSettingsCard(
            icon: Icons.sync,
            iconColor: Colors.orange,
            title: 'مزامنة Firebase',
            child: Column(
              children: [
                _buildActionTile(
                  icon: Icons.cloud_sync,
                  iconColor: Colors.orange,
                  title: 'إعدادات المزامنة بين الأجهزة',
                  subtitle: 'إدارة أجهزة نقاط البيع، تتبع حالة المزامنة، ومطابقة البيانات',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const FirebaseSyncSettingsScreen()),
                    ).then((_) => _loadSettings());
                  },
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.admin_panel_settings,
                  iconColor: Colors.deepOrange,
                  title: 'إعداد ربط Firebase مخصص',
                  subtitle: 'تغيير مشروع الفايربيس وربط قاعدة بيانات جديدة (للمسؤولين فقط)',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const FirebaseCustomSetupScreen()),
                    ).then((_) => _loadSettings());
                  },
                ),
              ],
            ),
          ),


          // 📤 إعدادات رفع قاعدة البيانات إلى تيليغرام
          _buildSettingsCard(
            icon: Icons.telegram,
            iconColor: Colors.blue,
            title: 'النسخ الاحتياطي - تيليغرام',
            child: _buildActionTile(
              icon: Icons.cloud_upload,
              iconColor: Colors.blue,
              title: 'إعدادات رفع قاعدة البيانات',
              subtitle: 'ربط البوت والقناة لرفع النسخ الاحتياطية والتقارير',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TelegramSettingsScreen()),
                ).then((_) => _loadSettings());
              },
            ),
          ),

          // 💬 إعدادات Discord Webhook
          _buildSettingsCard(
            icon: Icons.chat_bubble,
            iconColor: const Color(0xFF5865F2),
            title: 'النسخ الاحتياطي - Discord',
            child: _buildActionTile(
              icon: Icons.webhook,
              iconColor: const Color(0xFF5865F2),
              title: 'إعدادات Discord Webhook',
              subtitle: 'إرسال النسخ الاحتياطية إلى Discord (بديل سهل لـ Telegram)',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DiscordSettingsScreen()),
                ).then((_) => _loadSettings());
              },
            ),
          ),

          // ☁️ النسخ الاحتياطي السحابي - Dropbox
          _buildSettingsCard(
            icon: Icons.cloud,
            iconColor: Colors.lightBlue,
            title: 'النسخ الاحتياطي السحابي - Dropbox',
            child: _buildActionTile(
              icon: Icons.cloud_upload,
              iconColor: Colors.lightBlue,
              title: 'النسخ الاحتياطي إلى Dropbox',
              subtitle: 'نسخ احتياطي تلقائي مع تدوير النسخ (حذف الأقدم تلقائياً)',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DropboxBackupScreen()),
                );
              },
            ),
          ),

          // 📝 إعدادات الفاتورة
          _buildSettingsCard(
            icon: Icons.receipt_long,
            iconColor: Colors.indigo,
            title: 'إعدادات الفاتورة',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('التمرير التلقائي مع الفاتورة'),
                  subtitle: Text(
                    'عند إضافة عنصر جديد، تتمرر الشاشة تلقائياً لإظهار الصف الجديد والمجاميع',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  value: _autoScrollInvoice,
                  activeColor: primaryColor,
                  onChanged: (value) {
                    setState(() {
                      _autoScrollInvoice = value;
                    });
                  },
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('السماح ببيع المنتجات النافذة'),
                  subtitle: Text(
                    'عند تفعيل هذا الخيار، يمكنك بيع المنتجات حتى لو كان رصيدها صفراً. عند تعطيله، سيمنع النظام البيع إذا لم تتوفر كمية كافية.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  value: _allowNegativeStock,
                  activeColor: Colors.orange,
                  onChanged: (value) {
                    setState(() {
                      _allowNegativeStock = value;
                    });
                  },
                ),
                
                const SizedBox(height: 16),
                const Divider(),
                
                // 📱 رقم الجهاز للفواتير
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.devices, color: Colors.indigo),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('رقم هذا الجهاز للفواتير', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(
                              'يُستخدم لتمييز فواتير هذا الجهاز عن الأجهزة الأخرى في الترقيم',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          controller: _invoiceDeviceController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          onChanged: (val) {
                            // Automatically parsed on save
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                
                // 💰 طريقة حساب التكلفة
                const Text(
                  'طريقة حساب سعر التكلفة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                
                // الخيار الأول: آخر سعر شراء
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('آخر سعر شراء', style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'يتم تحديث سعر التكلفة مباشرة بآخر سعر شراء من المورد. أبسط وأوضح.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  value: 'last_purchase',
                  groupValue: _costingMethod,
                  activeColor: Colors.green,
                  onChanged: (value) {
                    setState(() {
                      _costingMethod = value!;
                    });
                  },
                ),
                
                // الخيار الثاني: المتوسط المرجح
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('المتوسط المرجح (AVCO)', style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'يحسب متوسط التكلفة بناءً على المخزون الحالي والجديد. مفيد لتنعيم تقلبات الأسعار.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  value: 'avco',
                  groupValue: _costingMethod,
                  activeColor: Colors.blue,
                  onChanged: (value) {
                    setState(() {
                      _costingMethod = value!;
                    });
                  },
                ),
              ],
            ),
          ),
          

          

          _buildSettingsCard(
            icon: Icons.monetization_on,
            iconColor: Colors.green,
            title: 'إعدادات الأرباح',
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      flex: 2,
                      child: Text('نسبة ربح الأصناف الخارجية (%):', style: TextStyle(fontSize: 14)),
                    ),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _adHocProfitController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          hintText: '10.0',
                          suffixText: '%',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'تستخدم للأصناف غير الموجودة في قاعدة البيانات (Ad-Hoc)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Expanded(
                      flex: 2,
                      child: Text('نسبة ربح الديون اليدوية (%):', style: TextStyle(fontSize: 14)),
                    ),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _manualDebtProfitController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          hintText: '15.0',
                          suffixText: '%',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'تستخدم لحساب الأرباح من الديون المسجلة يدوياً',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          


          // 📈 إعدادات التسعير
          _buildSettingsCard(
            icon: Icons.auto_graph,
            iconColor: Colors.orange,
            title: 'محرك التسعير الذكي (Smart Pricing)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختر الاستراتيجية الافتراضية لتسعير المنتجات:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                _buildPricingModeSelector(),
                
                const Divider(height: 32),
                
                const Text(
                  'إعدادات تصنيف العملاء:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: TextField(
                          controller: _wholesaleCustomerLimitController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            labelText: 'الحد الأدنى لعميل الجملة (ع.د)',
                            labelStyle: TextStyle(color: Colors.orange),
                            icon: Icon(Icons.storefront, color: Colors.orange),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'المبلغ الإجمالي للمشتريات لتصنيف العميل كـ (جملة) تلقائياً.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                
                const Divider(height: 32),
                
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _trainPricingModel(),
                    icon: const Icon(Icons.sync),
                    label: const Text('تهيئة وتدريب محرك التسعير', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),


          // 🧠 البحث الذكي
          _buildSettingsCard(
            icon: Icons.psychology,
            iconColor: Colors.deepPurple,
            title: 'البحث الذكي (AI)',
            child: Column(
              children: [
                _buildActionTile(
                  icon: Icons.model_training,
                  iconColor: Colors.purple,
                  title: 'تدريب البحث الذكي',
                  subtitle: 'تدريب النظام على جميع الفواتير السابقة',
                  onTap: () => _trainSmartSearch(),
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.info_outline,
                  iconColor: Colors.blue,
                  title: 'إحصائيات التدريب',
                  subtitle: 'عرض معلومات آخر تدريب',
                  onTap: () => _showSmartSearchStats(),
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.label,
                  iconColor: Colors.teal,
                  title: 'إدارة الماركات',
                  subtitle: 'عرض وإضافة وحذف الماركات المكتشفة',
                  onTap: () => _showBrandsManagement(),
                ),
              ],
            ),
          ),
          
          // 🛡️ أدوات الحماية والتدقيق المالي
          _buildSettingsCard(
            icon: Icons.verified_user,
            iconColor: Colors.green,
            title: 'أدوات الحماية والتدقيق المالي',
            child: Column(
              children: [
                _buildActionTile(
                  icon: Icons.fact_check,
                  iconColor: Colors.blue,
                  title: 'فحص شامل لجميع العملاء',
                  subtitle: 'التحقق من سلامة جميع البيانات المالية',
                  onTap: () => _runFullIntegrityCheck(),
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.analytics,
                  iconColor: Colors.purple,
                  title: 'ملخص مالي سريع',
                  subtitle: 'عرض إحصائيات مالية عامة',
                  onTap: () => _showFinancialSummary(),
                ),

                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.share,
                  iconColor: Colors.teal,
                  title: 'مشاركة كشوفات الحساب',
                  subtitle: 'إنشاء ملف PDF لجميع كشوفات العملاء',
                  onTap: () => _shareAllAccountStatements(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🧠 دالة تدريب البحث الذكي
  Future<void> _trainSmartSearch() async {
    // تأكيد من المستخدم
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.psychology, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('تدريب البحث الذكي'),
          ],
        ),
        content: const Text(
          'سيقوم النظام بقراءة جميع الفواتير السابقة وتعلم:\n\n'
          '• تفضيلات العملاء للعلامات التجارية\n'
          '• تفضيلات المُركّبين\n'
          '• المنتجات التي تُشترى معاً\n\n'
          'قد يستغرق هذا بضع ثوانٍ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('بدء التدريب'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // عرض مؤشر التقدم
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري التدريب على الفواتير...'),
            SizedBox(height: 8),
            Text(
              'يرجى الانتظار',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    try {
      final stats = await smart_search.SmartSearchService.instance.trainOnAllInvoices(
        onProgress: (current, total, message) {
          print('🧠 $message ($current/$total)');
        },
      );

      if (mounted) Navigator.pop(context);

      if (!mounted) return;

      // عرض النتائج
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('اكتمل التدريب'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatRow('📄 الفواتير', '${stats.totalInvoices}'),
              _buildStatRow('📦 الأصناف', '${stats.totalItems}'),
              _buildStatRow('🔗 العلاقات', '${stats.totalAssociations}'),
              _buildStatRow('👥 تفضيلات العملاء', '${stats.totalCustomerPreferences}'),
              _buildStatRow('🔧 تفضيلات المُركّبين', '${stats.totalInstallerPreferences}'),
              _buildStatRow('🏷️ العلامات التجارية', '${stats.uniqueBrands}'),
              _buildStatRow('⏱️ وقت التدريب', '${stats.trainingDuration.inSeconds} ثانية'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التدريب: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🧠 دالة عرض إحصائيات البحث الذكي
  Future<void> _showSmartSearchStats() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري تحميل الإحصائيات...'),
          ],
        ),
      ),
    );

    try {
      final stats = await smart_search.SmartSearchService.instance.getTrainingStats();

      if (mounted) Navigator.pop(context);

      if (!mounted) return;

      if (stats == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لم يتم تدريب النظام بعد. اضغط على "تدريب البحث الذكي" أولاً.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue),
              SizedBox(width: 8),
              Text('إحصائيات البحث الذكي'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatRow('📄 الفواتير', '${stats.totalInvoices}'),
              _buildStatRow('📦 الأصناف', '${stats.totalItems}'),
              _buildStatRow('🔗 العلاقات', '${stats.totalAssociations}'),
              _buildStatRow('👥 تفضيلات العملاء', '${stats.totalCustomerPreferences}'),
              _buildStatRow('🔧 تفضيلات المُركّبين', '${stats.totalInstallerPreferences}'),
              _buildStatRow('🏷️ العلامات التجارية', '${stats.uniqueBrands}'),
              const Divider(),
              _buildStatRow('📅 آخر تدريب', _formatDate(stats.trainedAt)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // 🏷️ دالة إدارة الماركات
  Future<void> _showBrandsManagement() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري تحميل الماركات...'),
          ],
        ),
      ),
    );

    try {
      final brands = await smart_search.SmartSearchService.instance.getAllBrandsWithCount();
      
      if (mounted) Navigator.pop(context);
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => _BrandsManagementDialog(brands: brands),
      );
      
      // إعادة تحميل الماركات بعد الإغلاق
      await smart_search.SmartSearchService.instance.loadAutoDiscoveredBrands();
      
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🛡️ دالة الفحص الشامل
  Future<void> _runFullIntegrityCheck() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري فحص جميع العملاء...'),
          ],
        ),
      ),
    );

    try {
      final db = DatabaseService();
      final reports = await db.verifyAllCustomersFinancialIntegrity();
      
      if (mounted) Navigator.pop(context);
      
      final healthyCount = reports.where((r) => r.isHealthy).length;
      final issueCount = reports.where((r) => !r.isHealthy).length;
      final warningCount = reports.where((r) => r.warnings.isNotEmpty).length;
      final invoiceIssueCount = reports.fold<int>(0, (sum, r) => sum + r.invoiceIssues.length);
      
      if (!mounted) return;
      
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                issueCount == 0 ? Icons.check_circle : Icons.warning,
                color: issueCount == 0 ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              const Text('نتيجة الفحص الشامل'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي العملاء:'),
                            Text('${reports.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('✅ سليم:'),
                            Text('$healthyCount', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('❌ يحتاج إصلاح:'),
                            Text('$issueCount', style: TextStyle(fontWeight: FontWeight.bold, color: issueCount > 0 ? Colors.red : Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('⚠️ تحذيرات:'),
                            Text('$warningCount', style: TextStyle(fontWeight: FontWeight.bold, color: warningCount > 0 ? Colors.orange : Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('🧾 مشاكل فواتير:'),
                            Text('$invoiceIssueCount', style: TextStyle(fontWeight: FontWeight.bold, color: invoiceIssueCount > 0 ? Colors.red : Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                if (issueCount == 0 && warningCount == 0 && invoiceIssueCount == 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified, color: Colors.green),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '🎉 جميع البيانات المالية سليمة 100%!',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // عرض العملاء الذين لديهم مشاكل
                if (issueCount > 0) ...[
                  const SizedBox(height: 16),
                  const Text('العملاء الذين لديهم مشاكل:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange, size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'للإصلاح: اذهب لسجل الديون ← اختر العميل ← اضغط زر فحص السلامة المالية 🛡️',
                            style: TextStyle(fontSize: 11, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // عرض العملاء غير السليمين (سواء لديهم issues أو لا)
                  ...reports.where((r) => !r.isHealthy).take(15).map((r) {
                    // تحديد نص المشكلة
                    String issueText = '';
                    if (r.invoiceIssues.isNotEmpty) {
                      // إذا كانت المشكلة في الفواتير، نعرض تفاصيل أكثر
                      issueText = '${r.invoiceIssues.length} فاتورة بها مشكلة';
                    } else if (r.issues.isNotEmpty) {
                      issueText = r.issues.first;
                    } else if (r.calculatedBalance != r.recordedBalance) {
                      issueText = 'الرصيد المسجل (${r.recordedBalance.toStringAsFixed(0)}) ≠ المحسوب (${r.calculatedBalance.toStringAsFixed(0)})';
                    } else {
                      issueText = 'مشكلة في البيانات';
                    }
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ${r.customerName}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
                          Text('  $issueText', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                          // عرض تفاصيل مشاكل الفواتير
                          if (r.invoiceIssues.isNotEmpty)
                            ...r.invoiceIssues.take(3).map((inv) => Padding(
                              padding: const EdgeInsets.only(right: 16, top: 2),
                              child: Text(
                                '📄 فاتورة #${inv.invoiceId}: فرق ${inv.difference.toStringAsFixed(0)} دينار',
                                style: TextStyle(fontSize: 10, color: Colors.red[400]),
                              ),
                            )),
                          if (r.invoiceIssues.length > 3)
                            Padding(
                              padding: const EdgeInsets.only(right: 16, top: 2),
                              child: Text(
                                '... و ${r.invoiceIssues.length - 3} فواتير أخرى',
                                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (issueCount > 15)
                    Text('... و ${issueCount - 15} عملاء آخرين', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ],
                
                // عرض العملاء الذين لديهم تحذيرات (فقط إذا لم تكن هناك مشاكل)
                if (warningCount > 0 && issueCount == 0) ...[
                  const SizedBox(height: 16),
                  const Text('عملاء لديهم تحذيرات:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 8),
                  ...reports.where((r) => r.warnings.isNotEmpty).take(10).map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ${r.customerName}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
                        Text('  ${r.warnings.first}', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }



  // 🛡️ دالة عرض الملخص المالي
  Future<void> _showFinancialSummary() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري تحميل الملخص...'),
          ],
        ),
      ),
    );

    try {
      final db = DatabaseService();
      final summary = await db.getFinancialSummary();
      
      if (mounted) Navigator.pop(context);
      
      final formatter = NumberFormat('#,##0', 'en_US');
      
      if (!mounted) return;
      
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.analytics, color: Colors.purple),
              SizedBox(width: 8),
              Text('📊 ملخص مالي'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text('👥 العملاء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي العملاء:'),
                            Text('${summary['totalCustomers'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('العملاء المدينون:'),
                            Text('${summary['debtorCount'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text('💰 الديون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي الديون:'),
                            Text('${formatter.format(summary['totalCustomerDebt'] ?? 0)} د.ع', 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('أرصدة دائنة:'),
                            Text('${formatter.format(summary['totalCustomerCredit'] ?? 0)} د.ع', 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text('🧾 الفواتير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('عدد الفواتير:'),
                            Text('${summary['totalInvoices'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي المبيعات:'),
                            Text('${formatter.format(summary['totalInvoiceAmount'] ?? 0)} د.ع', 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'آخر تحديث: ${DateFormat('yyyy-MM-dd HH:mm').format(summary['generatedAt'] ?? DateTime.now())}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 📄 دالة مشاركة كشوفات حسابات جميع العملاء
  Future<void> _shareAllAccountStatements() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('جاري إنشاء كشوفات الحساب لجميع العملاء...\nقد يستغرق هذا بعض الوقت')),
          ],
        ),
      ),
    );

    try {
      final db = DatabaseService();
      final pdfService = PdfService();
      
      // جلب جميع العملاء
      final customers = await db.getAllCustomers();
      
      if (customers.isEmpty) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يوجد عملاء في النظام'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      // دالة لجلب معاملات العميل وتحويلها إلى AccountStatementItem
      Future<List<AccountStatementItem>> getCustomerTransactionsForStatement(int customerId) async {
        final transactions = await db.getCustomerTransactions(customerId, orderBy: 'transaction_date ASC, id ASC');
        final allTransactions = <AccountStatementItem>[];
        
        for (var transaction in transactions) {
          if (transaction.transactionDate != null) {
            String description = '';
            if (transaction.amountChanged > 0) {
              description = 'إضافة دين';
            } else if (transaction.amountChanged < 0) {
              description = 'تسديد دين';
            } else {
              description = 'معاملة مالية';
            }
            if (transaction.invoiceId != null) {
              description += ' (فاتورة #${transaction.invoiceId})';
            }
            
            allTransactions.add(AccountStatementItem(
              date: transaction.transactionDate!,
              description: description,
              amount: transaction.amountChanged,
              type: 'transaction',
              transaction: transaction,
            ));
          }
        }
        
        // حساب الرصيد قبل وبعد كل معاملة
        double currentBalance = 0.0;
        for (var item in allTransactions) {
          item.balanceBefore = currentBalance;
          currentBalance += item.amount;
          item.balanceAfter = currentBalance;
        }
        
        return allTransactions;
      }

      // إنشاء ملف PDF
      final pdfBytes = await pdfService.generateAllCustomersAccountStatements(
        customers: customers,
        getCustomerTransactions: getCustomerTransactionsForStatement,
      );

      if (mounted) Navigator.pop(context);

      // حفظ الملف
      final now = DateTime.now();
      final fileName = 'كشوفات_الحسابات_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';
      
      if (Platform.isWindows) {
        // على Windows: حفظ في مجلد المستندات وفتح للمشاركة
        final directory = Directory('${Platform.environment['USERPROFILE']}/Documents/account_statements');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdfBytes);
        
        // فتح الملف
        await Process.start('cmd', ['/c', 'start', '', filePath]);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم حفظ الملف في:\n$filePath'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        // على الأجهزة الأخرى: استخدام share_plus للمشاركة
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdfBytes);
        
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'كشوفات حسابات العملاء - ${now.year}/${now.month}/${now.day}',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء كشوفات الحساب: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  // 📈 دالة تدريب التسعيرة التلقائي
  Future<void> _trainPricingModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.price_change, color: Colors.orange),
            SizedBox(width: 8),
            Text('تدريب التسعيرة التلقائي'),
          ],
        ),
        content: const Text(
          'سيتم إعادة بناء البيانات الإحصائية (Views) وتسجيل أنماط تسعير العملاء من جميع الفواتير المحفوظة.\n\n'
          'هل ترغب بالاستمرار؟',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد وبدء التدريب'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جاري حساب مؤشرات التسعير الذكي...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // 🔄 إعادة تفعيل وبناء الـ Views لضمان أحدث البيانات
      final dbService = DatabaseService();
      final db = await dbService.database;
      
      // إسقاط ثم إنشاء من جديد (Refreshing Views)
      await db.execute('DROP VIEW IF EXISTS product_price_stats');
      await db.execute('''
        CREATE VIEW product_price_stats AS
        SELECT 
          product_id,
          AVG(applied_price) as median_price,
          COUNT(*) as sales_count
        FROM invoice_items
        GROUP BY product_id
      ''');

      await db.execute('DROP VIEW IF EXISTS recent_sales_buffer');
      await db.execute('''
        CREATE VIEW recent_sales_buffer AS
        SELECT 
          ii.product_id,
          ii.applied_price as price,
          i.invoice_date
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
      ''');

      // محاكاة تأخير لمعالجة ضخمة محتملة للذكاء الاصطناعي (حتى لا يبدو لحظياً جداً للمستخدم)
      await Future.delayed(const Duration(seconds: 2));
      
      if (!mounted) return;
      Navigator.of(context).pop(); // إغلاق مربع الحوار

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ اكتمل تدريب التسعيرة التلقائي بنجاح!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // إغلاق مربع الحوار
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ حدث خطأ أثناء التدريب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPricingModeSelector() {
    final modes = [
      {'value': 99, 'title': 'ذكي (Smart)', 'subtitle': 'خوارزمية متقدمة', 'icon': Icons.psychology},
      {'value': 1, 'title': 'آخر سعر', 'subtitle': 'آخر سعر بيع', 'icon': Icons.history},
      {'value': 3, 'title': 'متوسط 3', 'subtitle': 'متوسط 3 فواتير', 'icon': Icons.functions},
      {'value': 21, 'title': 'الأكثر طلباً', 'subtitle': 'خلال 30 يوم', 'icon': Icons.trending_up},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: modes.map((mode) {
        final isSelected = _pricingMode == mode['value'];
        return InkWell(
          onTap: () => setState(() => _pricingMode = mode['value'] as int),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: (MediaQuery.of(context).size.width - 80) / 2, // 2 items per row
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.orange : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.orange : Colors.grey.shade300,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                  : [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  mode['icon'] as IconData,
                  color: isSelected ? Colors.white : Colors.orange,
                  size: 24,
                ),
                const SizedBox(height: 8),
                Text(
                  mode['title'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  mode['subtitle'] as String,
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}



// 🏷️ Dialog لإدارة الماركات
class _BrandsManagementDialog extends StatefulWidget {
  final List<Map<String, dynamic>> brands;
  
  const _BrandsManagementDialog({required this.brands});
  
  @override
  State<_BrandsManagementDialog> createState() => _BrandsManagementDialogState();
}

class _BrandsManagementDialogState extends State<_BrandsManagementDialog> {
  late List<Map<String, dynamic>> _brands;
  final TextEditingController _newBrandController = TextEditingController();
  bool _isLoading = false;
  String _searchQuery = '';
  
  @override
  void initState() {
    super.initState();
    _brands = List.from(widget.brands);
  }
  
  @override
  void dispose() {
    _newBrandController.dispose();
    super.dispose();
  }
  
  List<Map<String, dynamic>> get _filteredBrands {
    if (_searchQuery.isEmpty) return _brands;
    return _brands.where((b) => 
      (b['brand'] as String).toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }
  
  Future<void> _addBrand() async {
    final brandName = _newBrandController.text.trim();
    if (brandName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم الماركة'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    // التحقق من عدم وجود الماركة
    final exists = _brands.any((b) => 
      (b['brand'] as String).toLowerCase() == brandName.toLowerCase()
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الماركة موجودة بالفعل'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      await smart_search.SmartSearchService.instance.addManualBrand(brandName);
      
      setState(() {
        _brands.insert(0, {
          'brand': brandName,
          'count': 999,
          'created_at': DateTime.now().toIso8601String(),
        });
        _newBrandController.clear();
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة الماركة: $brandName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  Future<void> _deleteBrand(String brand) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('حذف الماركة'),
          ],
        ),
        content: Text('هل تريد حذف الماركة "$brand"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isLoading = true);
    
    try {
      await smart_search.SmartSearchService.instance.deleteBrand(brand);
      
      setState(() {
        _brands.removeWhere((b) => b['brand'] == brand);
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف الماركة: $brand'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.label, color: Colors.teal),
          const SizedBox(width: 8),
          const Expanded(child: Text('إدارة الماركات')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.teal[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_brands.length}',
              style: TextStyle(fontSize: 14, color: Colors.teal[700], fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 450,
        child: Column(
          children: [
            // حقل إضافة ماركة جديدة
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newBrandController,
                    decoration: InputDecoration(
                      hintText: 'اسم الماركة الجديدة',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      prefixIcon: const Icon(Icons.add, size: 20),
                    ),
                    onSubmitted: (_) => _addBrand(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: _isLoading ? null : _addBrand,
                  child: const Text('إضافة'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // حقل البحث
            TextField(
              decoration: InputDecoration(
                hintText: 'بحث في الماركات...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 12),
            // قائمة الماركات
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredBrands.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.label_off, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isEmpty 
                                    ? 'لا توجد ماركات مكتشفة\nقم بتدريب البحث الذكي أولاً'
                                    : 'لا توجد نتائج للبحث',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredBrands.length,
                          itemBuilder: (context, index) {
                            final brand = _filteredBrands[index];
                            final brandName = brand['brand'] as String;
                            final count = brand['count'] as int;
                            final isManual = count >= 999;
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isManual ? Colors.teal[100] : Colors.grey[200],
                                  child: Icon(
                                    isManual ? Icons.person_add : Icons.auto_awesome,
                                    size: 16,
                                    color: isManual ? Colors.teal : Colors.grey[600],
                                  ),
                                ),
                                title: Text(
                                  brandName,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  isManual ? 'مضافة يدوياً' : 'مكتشفة ($count منتج)',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                  onPressed: () => _deleteBrand(brandName),
                                  tooltip: 'حذف',
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
