import '../widgets/popup_screens.dart'; // 🪟
import '../widgets/item_code_keyboard_tile.dart'; // ⌨️
import 'dart:io';
import 'invoice_entry_layout_screen.dart'; // 🧩
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐 حراسة الويب
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';

import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/widgets/app_side_nav.dart';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/printing_service_factory.dart';
import 'package:alnaser/services/thermal_receipt_service.dart';
import 'package:intl/intl.dart';

import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart'; // 🌐 مشاركة وطباعة الويب
import '../services/database_service.dart';
import '../services/backup_files.dart';
import '../services/database/core/migration_guard.dart';
import '../widgets/migration_guard_views.dart';
import '../services/pdf_service.dart';
import '../services/invoice_settings_service.dart';
import 'package:share_plus/share_plus.dart';
import 'alert_settings_screen.dart'; // 🔔
import 'invoice_design_screen.dart'; // 🧳 تصميم الفاتورة
import 'telegram_settings_screen.dart'; // 📤 إعدادات تيليغرام
import '../owner/owner_access.dart'; // 👑 ميزات حساب المالك
import '../erp/erp_common.dart' show HubSection, HubTile;
import '../services/upload_targets.dart';
import '../owner/owner_settings_cards.dart';
import '../widgets/database_location_card.dart'; // 📂 مكان قاعدة البيانات
import 'discord_settings_screen.dart'; // 💬 إعدادات Discord
import 'dropbox_backup_screen.dart'; // ☁️ النسخ الاحتياطي السحابي
import 'firebase_sync_settings_screen.dart';
import 'firebase_custom_setup_screen.dart';
import 'web_hosting_guide_screen.dart'; // 🌐 استضافة الويب
import 'package:file_picker/file_picker.dart';
import '../services/license_service.dart';
import '../widgets/stay_logged_in_tile.dart';
import '../inventory/product_entry_mode.dart';
import '../invoice_designer/invoice_designer_screen.dart';
import '../invoice_designer/voucher_designer_screen.dart'; // 🧾 مصمم السندات
import '../accounting/screens/acc_ui.dart' show requirePermission, accAppBar;
import '../erp/erp_kit.dart' show ErpDialog;
import '../widgets/settings_kit.dart' show SetBanner, SetBannerKind, SetSteps;
import '../models/app_user.dart' show AppPermissions;
import '../erp/erp_settings_screen.dart';
import '../erp/activity/activity_log.dart' show ActivityLogScreen;
import '../devtools/stress_test/stress_test_screen.dart'; // 🧪

import '../models/account_statement_item.dart';
import 'duplicate_customers_screen.dart'; // 🔗 دمج الحسابات المكررة
import '../services/smart_search/smart_search.dart' as smart_search; // 🧠 البحث الذكي
import '../widgets/loading_dialog.dart';


class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  /// 🧭 القسم المطلوب فتحه (من اللوحة الجانبية) — يُطبَّق ثم يُمسح
  static final ValueNotifier<String?> requestedSection = ValueNotifier<String?>(null);
  static int _openCount = 0;

  /// يفتح الإعدادات على قسم معيّن؛ إن كانت مفتوحة يبدّل القسم فقط
  static void openSection(BuildContext context, String title) {
    requestedSection.value = title;
    if (_openCount <= 0) Navigator.of(context).pushNamed('/general_settings');
  }

  /// 🧭 أقسام الإعدادات للوحة الجانبية — العناوين يجب أن تطابق _SettingsSection أدناه
  static List<HubSection> menu(BuildContext context, void Function(Widget) go) {
    HubTile t(String title, IconData icon) =>
        HubTile(title, icon, const Color(0xFF64748B), () => openSection(context, title), permission: AppPermissions.settings);
    return [
      HubSection('الأقسام', [
        t('الحساب والموظفون', Icons.verified_user_outlined),
        if (OwnerAccess.enabled) t('ميزات المالك', Icons.workspace_premium_outlined),
        t('الفاتورة والطباعة', Icons.receipt_long_outlined),
        t('الأسعار والأرباح', Icons.trending_up),
        t('النسخ الاحتياطي والمزامنة', Icons.cloud_sync_outlined),
        t('الواجهة', Icons.dashboard_customize_outlined),
        t('النظام والأدوات', Icons.build_circle_outlined),
      ]),
    ];
  }

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  late AppSettings _appSettings;
  bool _isLoadingSettings = true;
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
  final TextEditingController _discountProfitPctController = TextEditingController(); // 🏷️
  String _voucherMode = 'ask'; // 🧾
  
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
  
  // 🖨️ إعدادات الطابعات
  List<PrinterDevice> _availablePrinters = [];
  List<PrinterDevice> _usbPrinters = [];
  PrinterDevice? _posThermalPrinter;
  PrinterDevice? _invoicePrinter;
  bool _loadingPrinters = false;
  bool _scanningUsb = false;
  bool _showSideNav = false;
  bool _enableSmartSearchRamCache = true; // 🧠
  String _tgRegularMode = 'each'; // 📤 each / combined / off
  String _tgPosMode = 'each';
  bool _tgResendEdited = true;
  List<String> _uploadOrder = List.of(UploadTargets.all); // ☁️ ترتيب وجهات زر الرفع
  Set<String> _uploadDisabled = {};
  String _screenOrientation = 'landscape';
  bool _isSyncAllowed = false;

  @override
  void initState() {
    super.initState();
    GeneralSettingsScreen._openCount++;
    GeneralSettingsScreen.requestedSection.addListener(_onSectionRequest);
    _loadSettings();
  }

  /// الإعدادات مفتوحة وطُلب قسم من اللوحة الجانبية ⇒ أعد البناء ليُطبَّق
  void _onSectionRequest() {
    if (GeneralSettingsScreen.requestedSection.value != null && mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    _appSettings = await SettingsManager.getAppSettings();
    
    // تحميل الترخيص والاتجاه
    final storedLicense = LicenseService().getStoredLicense();
    _isSyncAllowed = storedLicense?.isSyncAllowed ?? false;
    _screenOrientation = GetStorage().read('screen_orientation') ?? 'landscape';
    
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
    _discountProfitPctController.text = _appSettings.discountProfitPercent.toString();
    _voucherMode = _appSettings.adjustmentVoucherMode;
    
    // تحميل إعدادات الفاتورة والتسعير
    _autoScrollInvoice = _appSettings.autoScrollInvoice;
    _allowNegativeStock = _appSettings.allowNegativeStock;
    _costingMethod = _appSettings.costingMethod;
    _pricingMode = _appSettings.pricingMode;
    _wholesaleCustomerLimitController.text = _appSettings.wholesaleCustomerLimit.toString();
    _showSideNav = _appSettings.showSideNav;
    _enableSmartSearchRamCache = _appSettings.enableSmartSearchRamCache;
    _tgRegularMode = _appSettings.telegramRegularInvoicesMode;
    _tgPosMode = _appSettings.telegramPosInvoicesMode;
    _tgResendEdited = _appSettings.telegramResendEdited;
    _uploadOrder = UploadTargets.ordered(_appSettings.uploadOrder, owner: true);
    _uploadDisabled = _appSettings.uploadDisabled.toSet();
    
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
    _posThermalPrinter = await SettingsManager.getPosThermalPrinter();
    _invoicePrinter = await SettingsManager.getInvoicePrinter();
    final printingService = getPlatformPrintingService();
    final systemPrinters = await printingService.findSystemPrinters();
    final manualPrinters = await SettingsManager.getManualPrinters();
    
    _availablePrinters = [...manualPrinters, ...systemPrinters];
    
    if (_posThermalPrinter != null && 
        !_availablePrinters.any((p) => p.name == _posThermalPrinter!.name && p.address == _posThermalPrinter!.address)) {
      _availablePrinters.add(_posThermalPrinter!);
    }
    _savedSnapshot = _snapshot();
    if (mounted) {
      setState(() {
        _isLoadingSettings = false;
      });
    }
  }

  // ═══════════════ تغييرات غير محفوظة ═══════════════
  // بعض الإعدادات تُحفظ فوراً (مثل الشريط الجانبي واتجاه الشاشة)، وأغلبها كان
  // يحتاج زر الحفظ الصغير في الشريط العلوي — فالخروج بدونه كان يُضيع التعديل
  // بصمت. الآن: شريط سفلي يظهر عند وجود تعديل، وسؤال قبل الخروج.

  String? _savedSnapshot;

  String _snapshot() => [
        _autoScrollInvoice,
        _allowNegativeStock,
        _costingMethod,
        _pricingMode,
        _adHocProfitController.text,
        _manualDebtProfitController.text,
        _discountProfitPctController.text,
        _voucherMode,
        _wholesaleCustomerLimitController.text,
        _invoiceDeviceController.text,
        _companyDescriptionController.text,
        _storeSection,
        _branchName,
        _showSideNav,
        _enableSmartSearchRamCache,
        _tgRegularMode,
        _tgPosMode,
        _tgResendEdited,
        _uploadOrder.join(','),
        (_uploadDisabled.toList()..sort()).join(','),
      ].join('§');

  bool get _dirty => _savedSnapshot != null && _snapshot() != _savedSnapshot;

  Listenable get _fieldsListenable => Listenable.merge([
        _adHocProfitController,
        _manualDebtProfitController,
        _discountProfitPctController,
        _wholesaleCustomerLimitController,
        _invoiceDeviceController,
        _companyDescriptionController,
      ]);

  Future<void> _discardChanges() async {
    setState(() => _isLoadingSettings = true);
    await _loadSettings();
  }

  /// يُسأل قبل الخروج إن وُجد تعديل غير محفوظ. يعيد true إن جاز الخروج.
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => ErpDialog(
        title: 'تغييرات غير محفوظة',
        subtitle: 'عدّلت إعدادات ولم تحفظها بعد',
        icon: Icons.save_as_rounded,
        color: const Color(0xFFC2410C),
        width: 460,
        content: const Text('هل تريد حفظها قبل الخروج؟', style: TextStyle(height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('خروج بلا حفظ')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'save'),
            icon: const Icon(Icons.save_rounded),
            label: const Text('حفظ ثم خروج'),
          ),
        ],
      ),
    );
    if (r == 'save') {
      await _saveSettings();
      return true;
    }
    return r == 'discard';
  }

  Widget _saveBar() {
    return AnimatedBuilder(
      animation: _fieldsListenable,
      builder: (context, _) {
        final dirty = _dirty;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: !dirty
              ? const SizedBox(width: double.infinity)
              : SafeArea(
                  top: false,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F3460),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x330F3460), blurRadius: 18, offset: Offset(0, 6))],
                    ),
                    child: Row(children: [
                      const Icon(Icons.edit_note_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('لديك تغييرات غير محفوظة',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                      TextButton(
                        onPressed: _discardChanges,
                        style: TextButton.styleFrom(foregroundColor: Colors.white70),
                        child: const Text('تراجع'),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Ctrl + S',
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0F3460),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _saveSettings,
                          icon: const Icon(Icons.save_rounded, size: 19),
                          label: const Text('حفظ التغييرات', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ]),
                  ),
                ),
        );
      },
    );
  }

  /// غلاف الشاشة: سؤال قبل الخروج + Ctrl+S للحفظ + لون التبديلات كحلي.
  Widget _shell(Widget scaffold) {
    final base = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave() && mounted) nav.pop(result);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _saveSettings(),
        },
        child: Focus(
          autofocus: true,
          child: Theme(
            data: base.copyWith(colorScheme: base.colorScheme.copyWith(primary: primaryColor)),
            child: scaffold,
          ),
        ),
      ),
    );
  }
  
  Future<void> _showAddManualPrinterDialog() async {
    String name = '';
    String address = '';
    String connectionType = 'wifi';
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة طابعة يدوياً'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'اسم الطابعة'),
                onChanged: (v) => name = v,
              ),
              DropdownButtonFormField<String>(
                initialValue: connectionType,
                items: const [
                  DropdownMenuItem(value: 'wifi', child: Text('Wi-Fi / الشبكة')),
                  DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth')),
                ],
                onChanged: (v) => setDialogState(() => connectionType = v!),
                decoration: const InputDecoration(labelText: 'نوع الاتصال'),
              ),
              TextField(
                decoration: InputDecoration(
                  labelText: connectionType == 'wifi' ? 'IP Address' : 'MAC Address',
                  hintText: connectionType == 'wifi' ? '192.168.1.100' : '00:11:22:33:44:55',
                ),
                onChanged: (v) => address = v,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (name.isNotEmpty && address.isNotEmpty) {
                  final printer = PrinterDevice(
                    name: name,
                    address: address,
                    connectionType: connectionType == 'wifi' ? PrinterConnectionType.wifi : PrinterConnectionType.bluetooth,
                    port: connectionType == 'wifi' ? 9100 : null,
                  );
                  await SettingsManager.addManualPrinter(printer);
                  if (context.mounted) Navigator.pop(context);
                  _loadPrinters(); // إعادة التحميل لإظهارها
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  /// تحميل الطابعات المتاحة من النظام
  Future<void> _loadPrinters() async {
    setState(() => _loadingPrinters = true);
    try {
      final printingService = getPlatformPrintingService();
      final systemPrinters = await printingService.findSystemPrinters();
      final manualPrinters = await SettingsManager.getManualPrinters();
      _availablePrinters = [...manualPrinters, ...systemPrinters];
      
      _posThermalPrinter = await SettingsManager.getPosThermalPrinter();
      _invoicePrinter = await SettingsManager.getInvoicePrinter();
    } catch (e) {
      debugPrint('خطأ في تحميل الطابعات: $e');
    }
    if (mounted) {
      setState(() => _loadingPrinters = false);
    }
  }

  /// البحث عن الطابعات عبر USB OTG
  Future<void> _scanUsbPrinters() async {
    setState(() => _scanningUsb = true);
    try {
      final printingService = getPlatformPrintingService();
      final usbPrinters = await printingService.findUsbPrinters();
      setState(() {
        _usbPrinters = usbPrinters;
        // دمج الطابعات USB مع القائمة الكاملة
        _availablePrinters = [
          ..._availablePrinters.where((p) => p.connectionType != PrinterConnectionType.usb),
          ...usbPrinters,
        ];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(usbPrinters.isEmpty
                ? '⚠️ لم يتم اكتشاف أي طابعة USB. تحقق من توصيل كابل OTG.'
                : '✅ تم اكتشاف ${usbPrinters.length} طابعة USB'),
            backgroundColor: usbPrinters.isEmpty ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في البحث عن طابعات USB: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في البحث: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _scanningUsb = false);
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
      remainingAmountColor: _remainingAmountColor.toARGB32(),
      discountColor: _discountColor.toARGB32(),
      loadingFeesColor: _loadingFeesColor.toARGB32(),
      totalBeforeDiscountColor: _totalBeforeDiscountColor.toARGB32(),
      totalAfterDiscountColor: _totalAfterDiscountColor.toARGB32(),
      previousDebtColor: _previousDebtColor.toARGB32(),
      currentDebtColor: _currentDebtColor.toARGB32(),
      electricPhoneColor: _electricPhoneColor.toARGB32(),
      healthPhoneColor: _healthPhoneColor.toARGB32(),
      companyDescriptionColor: _companyDescriptionColor.toARGB32(),
      companyDescription: _companyDescriptionController.text,
      companyNameColor: _companyNameColor.toARGB32(),
      itemSerialColor: _itemSerialColor.toARGB32(),
      itemDetailsColor: _itemDetailsColor.toARGB32(),
      itemQuantityColor: _itemQuantityColor.toARGB32(),
      itemPriceColor: _itemPriceColor.toARGB32(),
      itemTotalColor: _itemTotalColor.toARGB32(),
      noticeColor: _noticeColor.toARGB32(),
      paidAmountColor: _paidAmountColor.toARGB32(),

      defaultAdHocProfitPercentage: double.tryParse(_adHocProfitController.text) ?? 10.0,
      manualDebtProfitPercentage: double.tryParse(_manualDebtProfitController.text) ?? 15.0,
      discountProfitPercent: (double.tryParse(_discountProfitPctController.text) ?? 10.0).clamp(0.0, 100.0),
      adjustmentVoucherMode: _voucherMode,
      autoScrollInvoice: _autoScrollInvoice,
      allowNegativeStock: _allowNegativeStock,
      costingMethod: _costingMethod,
      pricingMode: _pricingMode,
      wholesaleCustomerLimit: double.tryParse(_wholesaleCustomerLimitController.text) ?? 5000000.0,

      storeSection: _storeSection,
      branchName: _branchName,
      showSideNav: _showSideNav,
      enableSmartSearchRamCache: _enableSmartSearchRamCache,
      telegramRegularInvoicesMode: _tgRegularMode,
      telegramPosInvoicesMode: _tgPosMode,
      telegramResendEdited: _tgResendEdited,
      uploadOrder: List.of(_uploadOrder),
      uploadDisabled: _uploadDisabled.toList(),
    );
    await SettingsManager.saveAppSettings(_appSettings);
    
    // حفظ رقم الجهاز
    final parsedDeviceId = int.tryParse(_invoiceDeviceController.text.trim());
    if (parsedDeviceId != null) {
      await InvoiceSettingsService.setInvoiceDeviceId(parsedDeviceId);
      _invoiceDeviceId = parsedDeviceId;
    }
    
    _savedSnapshot = _snapshot();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF047857),
          content: Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text('تم حفظ الإعدادات بنجاح'),
          ]),
        ),
      );
    }
  }




  @override
  void dispose() {
    for (var controller in _phoneNumberControllers) {
      controller.dispose();
    }
    _companyDescriptionController.dispose();

    _adHocProfitController.dispose();
    _manualDebtProfitController.dispose();
    _discountProfitPctController.dispose();
    _wholesaleCustomerLimitController.dispose();
    GeneralSettingsScreen._openCount--;
    GeneralSettingsScreen.requestedSection.removeListener(_onSectionRequest);
    super.dispose();
  }


  static const Color primaryColor = Color(0xFF0F3460); // كحلي البرنامج (كان نيلياً مختلفاً)

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      hoverColor: iconColor.withValues(alpha: 0.05),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4)),
      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Colors.grey[400]),
      onTap: onTap,
    );
  }


  // 🧭 الإعدادات مقسّمة إلى أقسام (قائمة جانبية + محتوى) بدل صفحة واحدة طويلة.
  //    🧪 الوضع التجريبي انتقل إلى شاشة الدخول.
  int _settingsSection = 0;

  String _settingsQuery = '';

  Widget _buildSectionedSettings(List<_SettingsSection> sections) {
    final q = _settingsQuery.trim();
    final visible = [for (var i = 0; i < sections.length; i++) if (sections[i].matches(q)) i];
    // 🧭 طلب من اللوحة الجانبية: افتح القسم بالاسم وامسح البحث
    final want = GeneralSettingsScreen.requestedSection.value;
    if (want != null) {
      final i = sections.indexWhere((s) => s.title == want);
      if (i >= 0) _settingsSection = i;
      GeneralSettingsScreen.requestedSection.value = null;
    }
    var idx = _settingsSection.clamp(0, sections.length - 1);
    // البحث أخفى القسم المفتوح ⇒ افتح أول قسم مطابق
    if (q.isNotEmpty && visible.isNotEmpty && !visible.contains(idx)) idx = visible.first;
    final current = sections[idx];
    final wide = MediaQuery.of(context).size.width >= 900;

    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: ListView(
        key: ValueKey(idx),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(current.icon, color: primaryColor, size: 26),
            ),
            const SizedBox(width: 12),
            // Expanded: الوصف الطويل كان يتجاوز عرض الشاشة الضيقة
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(current.title,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                Text(current.description, style: const TextStyle(color: Color(0xFF64748B), height: 1.4)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          ...current.cards,
        ],
      ),
    );

    final search = TextField(
      onChanged: (v) => setState(() => _settingsQuery = v),
      decoration: InputDecoration(
        hintText: 'ابحث في الإعدادات… (طابعة، نسخة، موظف)',
        prefixIcon: const Icon(Icons.search_rounded),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF1F4F9),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );

    if (!wide) {
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 0), child: search),
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            children: [
              for (final i in visible)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    avatar: Icon(sections[i].icon, size: 18),
                    label: Text(sections[i].title),
                    selected: i == idx,
                    onSelected: (_) => setState(() => _settingsSection = i),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: content),
      ]);
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 290,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: BorderDirectional(end: BorderSide(color: Color(0xFFE6EBF2))),
        ),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 6), child: search),
          Expanded(
            child: visible.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('لا يوجد إعداد مطابق', style: TextStyle(color: Color(0xFF64748B))),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                    children: [
                      for (final i in visible)
                        _SettingsRailItem(
                          section: sections[i],
                          selected: i == idx,
                          color: primaryColor,
                          onTap: () => setState(() => _settingsSection = i),
                        ),
                    ],
                  ),
          ),
        ]),
      ),
      Expanded(
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: content),
        ),
      ),
    ]);
  }

  /// ☁️ وجهات زر «رفع البيانات» وترتيبها: اسحب ⠿ لتغيير الترتيب، والمفتاح للتفعيل
  Widget _uploadTargetsCard() {
    final owner = OwnerAccess.enabled;
    final list = UploadTargets.ordered(_uploadOrder, owner: owner);
    const icons = {
      UploadTargets.telegram: Icons.telegram,
      UploadTargets.dropbox: Icons.cloud_rounded,
      UploadTargets.discord: Icons.forum_rounded,
      UploadTargets.gdrive: Icons.add_to_drive_rounded,
    };
    const colors = {
      UploadTargets.telegram: Color(0xFF229ED9),
      UploadTargets.dropbox: Color(0xFF0061FE),
      UploadTargets.discord: Color(0xFF5865F2),
      UploadTargets.gdrive: Color(0xFF1A73E8),
    };
    return _buildSettingsCard(
      icon: Icons.cloud_upload_rounded,
      iconColor: Colors.indigo,
      title: 'زر «رفع البيانات»: الوجهات والترتيب',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('يرفع إلى المفعّل فقط، من الأعلى إلى الأسفل. اسحب ⠿ لتغيير الترتيب. '
              'الوجهة غير المربوطة تُتخطّى.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5)),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (oldI, newI) => setState(() {
            final t = list.removeAt(oldI);
            list.insert(newI, t);
            // Google Drive المخفي لغير المالك يبقى في آخر الترتيب المحفوظ
            _uploadOrder = [...list, ...UploadTargets.all.where((x) => !list.contains(x))];
          }),
          children: [
            for (var i = 0; i < list.length; i++)
              Material(
                key: ValueKey('ut-${list[i]}'),
                color: Colors.transparent,
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: _uploadDisabled.contains(list[i]) ? Colors.grey.shade300 : colors[list[i]],
                    child: _uploadDisabled.contains(list[i])
                        ? const Icon(Icons.block_rounded, size: 15, color: Colors.white)
                        : Text('${list.where((t) => !_uploadDisabled.contains(t)).toList().indexOf(list[i]) + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  title: Row(children: [
                    Icon(icons[list[i]], size: 18, color: colors[list[i]]),
                    const SizedBox(width: 8),
                    Text(UploadTargets.labels[list[i]]!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  subtitle: Text(UploadTargets.hints[list[i]]!, style: const TextStyle(fontSize: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                      value: !_uploadDisabled.contains(list[i]),
                      onChanged: (v) => setState(() {
                        if (v) {
                          _uploadDisabled.remove(list[i]);
                        } else {
                          _uploadDisabled.add(list[i]);
                        }
                      }),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.drag_indicator_rounded, color: Colors.black38)),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }

  /// 📤 طريقة رفع نوع من الفواتير: فاتورة فاتورة، ملف PDF واحد، أو بلا رفع
  Widget _invoiceUploadModeTile({
    required IconData icon,
    required String title,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    const labels = {'each': 'كل فاتورة وحدها', 'combined': 'ملف PDF واحد', 'off': 'لا ترفع'};
    const hints = {
      'each': 'كما الآن: لكل فاتورة ملف، وفوقه رقمها والفرع والمبلغ والربح',
      'combined': 'كل الفواتير في ملف واحد، وفوقه رسالة بأرقامها ومجموعها',
      'off': 'لا تُرفع هذه الفواتير إلى تيليغرام',
    };
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title),
      subtitle: Text(hints[value] ?? ''),
      trailing: DropdownButton<String>(
        value: labels.containsKey(value) ? value : 'each',
        underline: const SizedBox.shrink(),
        items: [for (final e in labels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF2)),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFEEF2F7)),
              const SizedBox(height: 8),
              child,
            ],
          ),
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
          color: isSelected ? color.withValues(alpha: 0.5) : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(type: MaterialType.transparency, child: ListTile(
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
      )),
    );
  }

  Future<void> _changeOrientation(String mode) async {
    setState(() => _screenOrientation = mode);
    await GetStorage().write('screen_orientation', mode);
    if (mode == 'auto') {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _checkLicenseUpgradeOnline() async {
    final licenseService = LicenseService();
    final currentLicense = licenseService.getStoredLicense();
    if (currentLicense == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الترخيص غير مفعّل على هذا الجهاز'), backgroundColor: Colors.orange),
      );
      return;
    }

    LoadingDialog.show(
      context,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جاري الاتصال بالسيرفر والتحقق من ترقية الحساب...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final hasInternet = await licenseService.hasInternetConnection();
      if (!hasInternet) {
        LoadingDialog.hide();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ يلزم الاتصال بالإنترنت للتحقق من ترقية الاشتراك!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final result = await licenseService.verifyWithServer();
      LoadingDialog.hide();

      if (result.success) {
        await _loadSettings();
        final updatedLicense = licenseService.getStoredLicense();
        
        String modeName = 'التطبيق الشامل الكامل مع المزامنة';
        if (updatedLicense?.appMode == 'debts_only') {
          modeName = 'سجل الديون والتصديق فقط';
        } else if (updatedLicense?.appMode == 'full_offline') {
          modeName = 'التطبيق الشامل الكامل (أوفلاين)';
        }

        String typeLabel = updatedLicense?.type == 'lifetime' || (updatedLicense?.expires.isEmpty ?? false)
            ? 'دائم — بلا تاريخ انتهاء'
            : 'اشتراك مؤقت حتى ${updatedLicense?.expires.split("T").first ?? ""}';

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.stars, color: Colors.amber, size: 28),
                  SizedBox(width: 8),
                  Text('تم التحديث والترقية بنجاح'),
                ],
              ),
              content: Text(
                '🎉 تم الاتصال بالسيرفر بنجاح وتحديث بيانات اشتراكك!\n\n'
                '• نوع الترخيص الحالي: $modeName\n'
                '• طابع الاشتراك: $typeLabel\n'
                '• خدمة المزامنة السحابية: ${updatedLicense?.isSyncAllowed == true ? "متاحة ومفعّلة ✅" : "غير مشمولة ❌"}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('موافق'),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل التحديث: ${result.error ?? result.message ?? "تعذر الاتصال بالسيرفر"}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      LoadingDialog.hide();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء التحديث: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showSelfUnbindDialog() async {
    final licenseService = LicenseService();
    final storedLicense = licenseService.getStoredLicense();

    if (storedLicense == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الترخيص غير مفعّل على هذا الجهاز'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // لا نتخلّص من المتحكم بعد الإغلاق مباشرة: حركة إغلاق النافذة ما زالت تستعمله.
    final passwordController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    bool obscurePassword = true;
    const danger = Color(0xFFC2410C);

    // النافذة تعيد رسالة النجاح؛ التنقّل يتم من سياق الشاشة لا من سياق النافذة المغلقة.
    final successMessage = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> confirm() async {
              final pwd = passwordController.text.trim();
              if (pwd.isEmpty) {
                setDialogState(() => errorMessage = 'أدخل كلمة سر حساب الترخيص لتأكيد الملكية');
                return;
              }
              setDialogState(() {
                isLoading = true;
                errorMessage = null;
              });
              try {
                final result = await licenseService.selfUnbindDevice(pwd);
                if (!dialogContext.mounted) return;
                if (result.success) {
                  Navigator.pop(dialogContext, result.message ?? 'تم تصفير الترخيص بنجاح');
                } else {
                  setDialogState(() {
                    isLoading = false;
                    errorMessage = result.message ?? 'فشل تصفير الجهاز';
                  });
                }
              } catch (e) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  isLoading = false;
                  errorMessage = 'حدث خطأ: $e';
                });
              }
            }

            return PopScope(
              canPop: !isLoading,
              child: ErpDialog(
                title: 'تصفير الترخيص ونقل الحساب',
                subtitle: 'الحساب: ${storedLicense.username}',
                icon: Icons.phonelink_erase_rounded,
                color: danger,
                width: 500,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('ماذا سيحدث؟',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    const SizedBox(height: 10),
                    const SetSteps([
                      'يُفكّ ارتباط هذا الجهاز بالترخيص على السيرفر.',
                      'يُسجَّل الخروج من هذا الجهاز فوراً.',
                      'تستطيع تسجيل الدخول بنفس الحساب من جهاز جديد.',
                    ], color: danger),
                    const SizedBox(height: 4),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      autofocus: true,
                      enabled: !isLoading,
                      onSubmitted: (_) => isLoading ? null : confirm(),
                      decoration: InputDecoration(
                        labelText: 'كلمة سر حساب الترخيص',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: obscurePassword ? 'إظهار' : 'إخفاء',
                          icon: Icon(obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: errorMessage == null
                          ? const SizedBox.shrink()
                          : Padding(
                              key: ValueKey(errorMessage),
                              padding: const EdgeInsets.only(top: 12),
                              child: SetBanner(errorMessage!, kind: SetBannerKind.error),
                            ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: danger),
                    onPressed: isLoading ? null : confirm,
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.phonelink_erase_rounded, size: 19),
                    label: const Text('تأكيد التصفير ونقل الترخيص'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (successMessage == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(successMessage), backgroundColor: Colors.green),
    );
    Navigator.of(context).pushNamedAndRemoveUntil('/license', (route) => false);
  }

  Future<void> _restoreDatabaseFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'اختر النسخة الاحتياطية (.db أو أرشيف تيليجرام .tar.xz أو .zip)',
      );

      if (result == null || result.files.isEmpty) return;

      final selectedFilePath = result.files.single.path;
      if (selectedFilePath == null || selectedFilePath.isEmpty) return;

      final file = File(selectedFilePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الملف المحدد غير موجود'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final fileName = file.path.split(Platform.pathSeparator).last;
      // 📦 أرشيف تيليجرام/zip/gz ⇒ تُستخرج القاعدة منه؛ ملف غير صالح يُرفض هنا قبل أي شيء
      final dbFile = await BackupFiles.extractDatabase(file);
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('تأكيد استعادة قاعدة البيانات'),
            ],
          ),
          content: Text(
            '⚠️ تنبيه هام:\nسيتم استبدال قاعدة البيانات الحالية بالملف المستورد ($fileName).\n\nهل أنت مأكد من استعادة وتطبيق هذه القاعدة الآن؟',
            style: const TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('استعادة واستبدال'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      if (mounted) {
        LoadingDialog.show(
          context,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('جاري استعادة قاعدة البيانات وتحديث النظام...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final success = await DatabaseService().restoreDatabaseFromFile(dbFile);

      LoadingDialog.hide(); // إغلاق حوار التحميل
      if (mounted) {
        if (success) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 8),
                  Text('تمت الاستعادة بنجاح'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 460),
                child: SingleChildScrollView(
                  child: SelectableText(restoreSummaryText(), style: const TextStyle(height: 1.55)),
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً'),
                ),
              ],
            ),
          );

          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
        }
      }
    } on MigrationGuardException catch (e) {
      LoadingDialog.hide();
      if (mounted) {
        await showMigrationRejectedDialog(context, e);
      }
    } catch (e) {
      LoadingDialog.hide();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت استعادة قاعدة البيانات: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSettings) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        appBar: accAppBar('الإعدادات العامة', icon: Icons.settings_rounded),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return _shell(Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: accAppBar(
        'الإعدادات العامة',
        icon: Icons.settings_rounded,
        subtitle: 'الحساب، الفاتورة والطباعة، الأسعار، النسخ الاحتياطي، الواجهة، النظام',
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded),
            tooltip: 'حفظ الإعدادات (Ctrl + S)',
            onPressed: _saveSettings,
          ),
        ],
      ),
      bottomNavigationBar: _saveBar(),
      body: Row(
        children: [
          if (AppSideNav.shouldShow(context, _appSettings))
            const AppSideNav(currentRoute: '/general_settings'),
          Expanded(
            child: _buildSectionedSettings(<_SettingsSection>[
        _SettingsSection(
          'الحساب والموظفون',
          Icons.verified_user_outlined,
          'الترخيص ونقل الجهاز، الموظفون والصلاحيات',
          keywords: 'ترخيص اشتراك ترقية جهاز نقل تصفير موظف موظفين صلاحيات كلمة سر دخول مستخدم مدير',
          [
          // 🔐 قسم إدارة الترخيص ونقل الجهاز
          _buildSettingsCard(
            icon: Icons.vpn_key_rounded,
            iconColor: Colors.amber.shade800,
            title: 'إدارة الترخيص وترقية الحساب',
            child: Column(
              children: [
                _buildActionTile(
                  icon: Icons.devices_rounded,
                  iconColor: const Color(0xFF0F3460),
                  title: 'الترخيص والأجهزة',
                  subtitle: 'معلومات الترخيص، الأجهزة المرتبطة، وإضافة جهاز برمز (من الجهاز الرئيسي)',
                  onTap: () => Navigator.pushNamed(context, '/license_devices'),
                ),
                const Divider(height: 1),
                if (!_isSyncAllowed) ...[
                  _buildActionTile(
                    icon: Icons.published_with_changes_rounded,
                    iconColor: Colors.teal,
                    title: 'فحص وترقية الاشتراك أونلاين',
                    subtitle: 'الاتصال بالسيرفر فوراً لتفعيل ترقية الحساب (من ديون إلى شامل أو مزامنة)',
                    onTap: _checkLicenseUpgradeOnline,
                  ),
                  const Divider(height: 1),
                ],
                _buildActionTile(
                  icon: Icons.phonelink_erase_rounded,
                  iconColor: Colors.orange.shade800,
                  title: 'تصفير الترخيص ونقل الحساب إلى جهاز آخر',
                  subtitle: 'فك ارتباط هذا الجهاز لتمكينك من تسجيل الدخول بنفس الحساب من كمبيوتر/هاتف جديد',
                  onTap: _showSelfUnbindDialog,
                ),
              ],
            ),
          ),
          // 👤 قسم إدارة المستخدمين
          _buildSettingsCard(
            icon: Icons.admin_panel_settings,
            iconColor: Colors.deepPurple,
            title: 'الموظفون والصلاحيات',
            child: _buildActionTile(
              icon: Icons.people,
              iconColor: Colors.deepPurple,
              title: 'إدارة الموظفين',
              subtitle: 'حسابات الدخول اليومية (منفصلة عن حساب الترخيص): أضف موظفاً، حدّد صلاحياته، غيّر كلمة سره',
              onTap: () {
                Navigator.pushNamed(context, '/user_management');
              },
            ),
          ),
          // 🔓 الدخول على هذا الجهاز
          _buildSettingsCard(
            icon: Icons.login_rounded,
            iconColor: const Color(0xFF0F3460),
            title: 'الدخول على هذا الجهاز',
            child: const StayLoggedInTile(),
          ),
          ],
        ),
        // 👑 ميزات المالك — تظهر لحساب المالك فقط، وغير موجودة لغيره إطلاقاً
        if (OwnerAccess.enabled)
          const _SettingsSection(
            'ميزات المالك',
            Icons.workspace_premium_outlined,
            'المؤسسون ونقاطهم، الرفع إلى Google Drive',
            keywords: 'مالك مؤسس مؤسسين فني فنيين نقاط جوجل درايف google drive رفع سجل الديون',
            [OwnerSettingsCards()],
          ),
        _SettingsSection(
          'الفاتورة والطباعة',
          Icons.receipt_long_outlined,
          'تصميم الفاتورة، إعدادات الفاتورة، الطابعات',
          keywords: 'سند إشعار مدين دائن إرجاع إضافة تسوية فاتورة تصميم مصمم شعار شركة هاتف طابعة طابعات إيصال حرارية كاشير A4 رقم الجهاز تمرير مخزون سالب كلفة تكلفة متوسط آخر سعر شراء مجاميع',
          [
          // 🧾 تصميم الفاتورة
          // 🧾 السند الذي يُطبع بعد إضافة أو إرجاع على فاتورة محفوظة
          _buildSettingsCard(
            icon: Icons.request_page_rounded,
            iconColor: Colors.red.shade700,
            title: 'السندات: قبض، صرف، إشعار مدين ودائن',
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.help_outline_rounded, color: Colors.indigo),
                title: const Text('الإعداد العام لطباعة السندات بعد الحفظ'),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text('يتبعه كل نوع سند لم تحدد له إعداداً في «مصمم السندات»، ومستند مرتجع المبيعات'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ask', label: Text('اسألني'), icon: Icon(Icons.help_outline)),
                    ButtonSegment(value: 'always', label: Text('اطبع دائماً'), icon: Icon(Icons.print_rounded)),
                    ButtonSegment(value: 'never', label: Text('لا تُظهر'), icon: Icon(Icons.block)),
                  ],
                  selected: {_voucherMode == 'always' || _voucherMode == 'never' ? _voucherMode : 'ask'},
                  onSelectionChanged: (s) => setState(() => _voucherMode = s.first),
                ),
              ),
              const Divider(height: 1),
              _buildActionTile(
                icon: Icons.dashboard_customize_outlined,
                iconColor: Colors.deepOrange,
                title: 'مصمم السندات — لكل نوع سند قوالبه',
                subtitle: 'سند قبض (تسديد دين)، سند قبض/صرف تعديل الفاتورة النقدية، إشعار مدين/دائن للآجلة: '
                    'اختر النوع، صمّمه من قالب جاهز أو ورقة بيضاء، وحدد هل يُسأل عن طباعته',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VoucherDesignerScreen()),
                ),
              ),
            ]),
          ),
          _buildSettingsCard(
            icon: Icons.receipt_long,
            iconColor: Colors.indigo,
            title: 'تصميم الفاتورة',
            child: Column(children: [
              _buildActionTile(
                icon: Icons.dashboard_customize_outlined,
                iconColor: Colors.deepOrange,
                title: 'مصمم الفاتورة — نماذج جاهزة وورقة بيضاء',
                subtitle: 'صمّم فاتورة A4 وإيصال 80 و58 ملم بالسحب: الأعمدة وترتيبها وعرضها، المجاميع مربعات أو قائمة، '
                    'واختر التصميم لكل نوع طباعة (الفاتورة، الطابعة الحرارية، إيصال الكاشير)',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InvoiceDesignerScreen()),
                ),
              ),
              const Divider(height: 1),
              _buildActionTile(
                icon: Icons.design_services,
                iconColor: Colors.indigo,
                title: 'معلومات الشركة والشعار (والتصميم الأصلي)',
                subtitle: 'اسم الشركة، الشعار، العنوان، حتى 4 هواتف، الرقم الضريبي — تُستعمل في كل التصاميم. '
                    'أعمدة الجدول من مصمم الفاتورة',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const InvoiceDesignScreen()),
                  ).then((_) => _loadSettings());
                },
              ),
              const Divider(height: 1),
              _buildActionTile(
                icon: Icons.view_week_outlined,
                iconColor: Colors.teal,
                title: 'تخطيط شاشة إنشاء الفاتورة',
                subtitle: 'الأعمدة الظاهرة وعرض كل عمود، ومكان المجاميع وزر الحفظ: لوحة جانبية أو شريط سفلي (جدول أعرض)',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InvoiceEntryLayoutScreen()),
                ),
              ),
              const Divider(height: 1),
              // 🧩 مكان المجاميع والدفع وزر الحفظ — مفتاح مباشر
              FutureBuilder<bool>(
                future: InvoiceSidePanelPref.load(),
                builder: (context, _) => ValueListenableBuilder<bool>(
                  valueListenable: InvoiceSidePanelPref.notifier,
                  builder: (context, side, _) => SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 2),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(side ? Icons.view_sidebar_outlined : Icons.call_to_action_outlined,
                          color: Colors.indigo, size: 24),
                    ),
                    title: const Text('عرض المجاميع في لوحة جانبية', style: TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      side
                          ? 'مفعّل: الإجمالي والخصم والدفع وزر الحفظ في لوحة على جانب شاشة الفاتورة'
                          : 'متوقف: تظهر في شريط مضغوط أسفل الجدول، والجدول بعرض الشاشة كاملاً',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    value: side,
                    onChanged: (v) => InvoiceSidePanelPref.set(v),
                  ),
                ),
              ),
            ]),
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
                  activeThumbColor: primaryColor,
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
                  activeThumbColor: Colors.orange,
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
                
                RadioGroup<String>(
                  groupValue: _costingMethod,
                  onChanged: (value) {
                    setState(() {
                      _costingMethod = value!;
                    });
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // الخيار الأول: آخر سعر شراء
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('آخر سعر شراء', style: TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          'يتم تحديث سعر التكلفة مباشرة بآخر سعر شراء من المورد. أبسط وأوضح.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        value: 'last_purchase',
                        activeColor: Colors.green,
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
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                ),
              ],
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
                            kIsWeb
                                ? 'الطباعة المباشرة غير مدعومة على الويب — استخدم مسار PDF من شاشة الفاتورة.'
                                : Platform.isAndroid || Platform.isIOS
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

                // ── أزرار الإجراءات ──
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _loadPrinters,
                      icon: const Icon(Icons.refresh),
                      label: const Text('تحديث القائمة'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _showAddManualPrinterDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة Wi-Fi/BT'),
                    ),
                  ],
                ),

                // ── قسم USB OTG ──
                const Divider(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.usb, color: Color(0xFF1A237E), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'طباعة عبر USB (Type-C / OTG)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'وصّل الطابعة بالهاتف عبر كابل OTG ثم اضغط بحث',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),

                      // زر البحث عن طابعات USB
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _scanningUsb ? null : _scanUsbPrinters,
                          icon: _scanningUsb
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.search_rounded),
                          label: Text(_scanningUsb ? 'جاري البحث...' : '🔍 بحث عن طابعة USB'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),

                      // عرض الطابعات المكتشفة عبر USB
                      if (_usbPrinters.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('الطابعات المكتشفة عبر USB:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 8),
                        ..._usbPrinters.map((printer) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.print, color: Color(0xFF1A237E), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(printer.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    if (printer.manufacturerName != null && printer.manufacturerName!.isNotEmpty)
                                      Text(printer.manufacturerName!, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                    Text(
                                      'VID: ${printer.vendorId?.toRadixString(16).toUpperCase()} • PID: ${printer.productId?.toRadixString(16).toUpperCase()}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  TextButton(
                                    onPressed: () => _selectInvoicePrinter(printer),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF1A237E),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    ),
                                    child: const Text('فواتير', style: TextStyle(fontSize: 11)),
                                  ),
                                  TextButton(
                                    onPressed: () => _selectPosThermalPrinter(printer),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.teal,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    ),
                                    child: const Text('كاشير', style: TextStyle(fontSize: 11)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          ],
        ),
        _SettingsSection(
          'الأسعار والأرباح',
          Icons.trending_up,
          'حساب الأرباح، التسعير، تنبيهات المخزون',
          keywords: 'ربح أرباح نسبة تسعير سعر جملة مفرد تنبيه تنبيهات نواقص ركود',
          [
          _buildSettingsCard(
            icon: Icons.monetization_on_rounded,
            iconColor: const Color(0xFF047857),
            title: 'إعدادات الأرباح',
            child: LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 620 ? 2 : 1;
              final w = (c.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                  width: w,
                  child: _percentTile(
                    controller: _adHocProfitController,
                    icon: Icons.add_shopping_cart_rounded,
                    color: const Color(0xFF047857),
                    title: 'ربح الأصناف الخارجية',
                    hint: '10',
                    help: 'للأصناف غير الموجودة في قاعدة البيانات (Ad-Hoc) — تُحسب أرباحها بهذه النسبة.',
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _percentTile(
                    controller: _manualDebtProfitController,
                    icon: Icons.edit_note_rounded,
                    color: const Color(0xFF2563EB),
                    title: 'ربح الديون اليدوية',
                    hint: '15',
                    help: 'لحساب الأرباح من الديون المسجّلة يدوياً (بلا فاتورة).',
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _percentTile(
                    controller: _discountProfitPctController,
                    icon: Icons.local_offer_rounded,
                    color: const Color(0xFFDC2626),
                    title: 'الخصم من الربح',
                    hint: '10',
                    help: 'في الفاتورة: الضغط على كلمة «الخصم» يقترح خصم هذه النسبة من ربح الفاتورة '
                        '(10% من ربح 200,000 = خصم 20,000). يمكن تغييرها في كل فاتورة.',
                  ),
                ),
              ]);
            }),
          ),
          // 📈 إعدادات التسعير
          _buildSettingsCard(
            icon: Icons.auto_graph_rounded,
            iconColor: const Color(0xFFEA580C),
            title: 'محرك التسعير الذكي',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('السعر المقترح عند إضافة مادة للفاتورة',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1E293B))),
                const SizedBox(height: 2),
                Text('يُقترح من سجل مبيعات المادة. «ذكي» لا يقترح سعراً أقل من الكلفة؛ بقية الأنماط تعطي السعر كما في السجل، وبلا سجل يبقى سعر المادة.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 12),
                _buildPricingModeSelector(),
                const SizedBox(height: 18),
                const Divider(height: 1, color: Color(0xFFEEF2F7)),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 620;
                  final field = TextField(
                    controller: _wholesaleCustomerLimitController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'الحد الأدنى لمشتريات عميل الجملة',
                      prefixIcon: Icon(Icons.storefront_rounded),
                      suffixText: 'د.ع',
                      helperText: '0 = تعطيل التصنيف التلقائي',
                    ),
                  );
                  const info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('تصنيف عملاء الجملة تلقائياً',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1E293B))),
                    SizedBox(height: 2),
                    Text('إذا بلغ مجموع مشتريات العميل (الفواتير المحفوظة) هذا المبلغ يُعامَل كعميل جملة في اقتراح السعر.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.5)),
                  ]);
                  return wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Expanded(child: info),
                          const SizedBox(width: 16),
                          SizedBox(width: 300, child: field),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          info,
                          const SizedBox(height: 10),
                          field,
                        ]);
                }),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFEEF2F7)),
                const SizedBox(height: 6),
                _buildActionTile(
                  icon: Icons.build_circle_outlined,
                  iconColor: const Color(0xFFEA580C),
                  title: 'إصلاح إحصائيات التسعير',
                  subtitle: 'يعيد إنشاء جداول الإحصاء التي يقرأ منها المحرك — استعمله إذا توقفت اقتراحات الأسعار عن الظهور',
                  onTap: _trainPricingModel,
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
          ],
        ),
        _SettingsSection(
          'النسخ الاحتياطي والمزامنة',
          Icons.cloud_sync_outlined,
          'استعادة القاعدة، تيليغرام، ديسكورد، دروب بوكس، المزامنة',
          keywords: 'رفع البيانات وجهات ترتيب جوجل درايف google drive مسار مكان مجلد ملف قاعدة البيانات نسخ احتياطي نسخة استعادة قاعدة تيليجرام تلغرام telegram discord dropbox فايربيس firebase مزامنة ويب متصفح',
          [
          // ☁️ زر «رفع البيانات»: إلى أين يرفع وبأي ترتيب
          _uploadTargetsCard(),
          // 📂 المسار الوحيد لقاعدة البيانات + فتح المجلد
          const DatabaseLocationCard(),
          // 📦 قسم استعادة النسخة الاحتياطية لقاعدة البيانات
          _buildSettingsCard(
            icon: Icons.settings_backup_restore_rounded,
            iconColor: Colors.blue.shade700,
            title: 'استعادة النسخة الاحتياطية لقاعدة البيانات',
            child: Column(
              children: [
                _buildActionTile(
                  icon: Icons.folder_open_rounded,
                  iconColor: Colors.blue.shade700,
                  title: 'استعادة قاعدة البيانات من ملف (.db)',
                  subtitle: 'استعادة الفواتير والديون والبيانات بعد تغيير الجهاز أو من ملف محفوض (مثل تيليجرام)',
                  onTap: _restoreDatabaseFromFile,
                ),
              ],
            ),
          ),
          // 📤 إعدادات رفع قاعدة البيانات إلى تيليغرام
          _buildSettingsCard(
            icon: Icons.telegram,
            iconColor: Colors.blue,
            title: 'النسخ الاحتياطي - تيليغرام',
            child: Column(children: [
              _buildActionTile(
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
              const Divider(height: 1),
              // 📤 طريقة رفع الفواتير مع زر «رفع قاعدة البيانات»
              _invoiceUploadModeTile(
                icon: Icons.receipt_long_rounded,
                title: 'رفع الفواتير العادية والجملة',
                value: _tgRegularMode,
                onChanged: (v) => setState(() => _tgRegularMode = v),
              ),
              _invoiceUploadModeTile(
                icon: Icons.point_of_sale_rounded,
                title: 'رفع إيصالات الكاشير',
                value: _tgPosMode,
                onChanged: (v) => setState(() => _tgPosMode = v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.edit_note_rounded, color: Colors.blue),
                title: const Text('إعادة رفع الفاتورة بعد تعديلها'),
                subtitle: const Text('فاتورة رُفعت ثم عُدّلت تُرفع نسختها الجديدة مع علامة «معدّلة»'),
                value: _tgResendEdited,
                onChanged: (v) => setState(() => _tgResendEdited = v),
              ),
            ]),
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
          // 🔥 إعدادات مزامنة Firebase (تظهر فقط إذا كانت المزامنة مشمولة في الترخيص)
          if (_isSyncAllowed)
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
                  const Divider(height: 1),
                  _buildActionTile(
                    icon: Icons.language_rounded,
                    iconColor: const Color(0xFF0288D1),
                    title: 'استضافة ورفع نسخة المتصفح (Web App)',
                    subtitle: 'معالج مصور لرفع متجرك مجاناً وافتتاحه من أي جوال أو جهاز عبر رابط خاص بك',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const WebHostingGuideScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),

          ],
        ),
        _SettingsSection(
          'الواجهة',
          Icons.dashboard_customize_outlined,
          'الشريط الجانبي، فتح الشاشات كنافذة، واجهة إدخال البضاعة، واتجاه الشاشة',
          keywords: 'شريط جانبي تنقل واجهة إدخال بضاعة اتجاه أفقي تدوير نافذة منبثقة بوب اب مسج بوكس popup رمز المادة لغة انجليزي لوحة المفاتيح كيبورد',
          [
          // 🧭 قسم إعدادات الواجهة والشريط الجانبي
          _buildSettingsCard(
            icon: Icons.view_sidebar_rounded,
            iconColor: const Color(0xFF1E1E2E),
            title: 'شريط التنقل الجانبي',
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('إظهار شريط التنقل الجانبي دائماً', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('يظهر تلقائياً على الشاشات الكبيرة (تابلت/ديسكتوب). يمكنك تفعيله هنا للهواتف أيضاً.', style: TextStyle(fontSize: 12)),
                  value: _showSideNav,
                  activeThumbColor: const Color(0xFF1E1E2E),
                  onChanged: (val) {
                    setState(() => _showSideNav = val);
                    _saveSettings();
                  },
                ),
              ],
            ),
          ),
          // 🪟 فتح الشاشات الرئيسية كنافذة منبثقة
          _buildSettingsCard(
            icon: Icons.picture_in_picture_alt_rounded,
            iconColor: const Color(0xFF0F2A4A),
            title: 'فتح الشاشات كنافذة منبثقة',
            child: const PopupScreensTile(),
          ),
          // ⌨️ رمز المادة بالإنجليزية تلقائياً
          _buildSettingsCard(
            icon: Icons.keyboard_alt_outlined,
            iconColor: const Color(0xFF1E3A8A),
            title: 'لغة الكتابة في رمز المادة',
            child: const ItemCodeKeyboardTile(),
          ),
          // 📦 واجهة إدخال البضاعة
          _buildSettingsCard(
            icon: Icons.inventory_2_outlined,
            iconColor: Colors.teal,
            title: 'إدخال البضاعة',
            child: const ProductEntryModeTile(),
          ),
          // 📱 إعدادات اتجاه الشاشة (الأندرويد والجوال)
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
            _buildSettingsCard(
              icon: Icons.screen_rotation,
              iconColor: Colors.purple,
              title: 'اتجاه الشاشة (الجوال والتابلت)',
              child: RadioGroup<String>(
                groupValue: _screenOrientation,
                onChanged: (val) => _changeOrientation(val!),
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      title: Text('أفقي ثابت (Landscape)'),
                      subtitle: Text('تثبيت الشاشة بالوضع الأفقي فقط وتفادي التدوير التلقائي'),
                      value: 'landscape',
                    ),
                    Divider(height: 1),
                    RadioListTile<String>(
                      title: Text('عرض تلقائي (Auto-Rotate)'),
                      subtitle: Text('السماح بالتدوير التلقائي حسب وضع الجوال ومستشعر الدوران'),
                      value: 'auto',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        _SettingsSection(
          'النظام والأدوات',
          Icons.build_circle_outlined,
          'الشبكة المحلية، سجل الحركات، البحث الذكي، التدقيق المالي',
          keywords: 'شبكة سيرفر طرفية سجل حركات بحث ذكي ماركات تدقيق فحص ملخص مالي كشوفات اختبار تحمل طباعة مخزون باركود ميزان',
          [
          // 🧭 أُزيلت هذه الأزرار من الرئيسية والأقسام وجُمعت هنا
          _buildSettingsCard(
            icon: Icons.tune,
            iconColor: Colors.indigo,
            title: 'الشبكة والطباعة والسجل',
            child: Column(
              children: [
                _buildActionTile(
                  icon: Icons.lan,
                  iconColor: Colors.blue,
                  title: 'الشبكة المحلية',
                  subtitle: 'جهاز مستقل، حاسبة السيرفر، أو طرفية',
                  onTap: () {
                    if (requirePermission(context, AppPermissions.networkSettings)) {
                      Navigator.pushNamed(context, '/network_settings');
                    }
                  },
                ),
                _buildActionTile(
                  icon: Icons.local_printshop_outlined,
                  iconColor: Colors.teal,
                  title: 'إعدادات الطباعة والمخزون',
                  subtitle: 'A4 أو 80mm، ملصقات الباركود، باركود الميزان، حسابات الجرد',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ErpSettingsScreen())),
                ),
                _buildActionTile(
                  icon: Icons.merge_type,
                  iconColor: Colors.deepOrange,
                  title: 'دمج الحسابات المكررة',
                  subtitle: 'حسابان بالاسم نفسه في سجل الديون ← حساب واحد (بتأكيدك ونسخة احتياطية)',
                  onTap: () {
                    if (requirePermission(context, AppPermissions.manageUsers)) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DuplicateCustomersScreen()));
                    }
                  },
                ),
                _buildActionTile(
                  icon: Icons.manage_search,
                  iconColor: Colors.purple,
                  title: 'سجل حركات النظام',
                  subtitle: 'من فعل ماذا ومتى',
                  onTap: () {
                    if (requirePermission(context, AppPermissions.manageUsers)) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityLogScreen()));
                    }
                  },
                ),
                // 🧪 اختبار التحمّل الحقيقي (للمدير فقط)
                _buildActionTile(
                  icon: Icons.science_outlined,
                  iconColor: Colors.deepOrange,
                  title: 'اختبار التحمّل والحسابات',
                  subtitle: 'آلاف الفواتير والمعاملات في القاعدة الحقيقية ثم مطابقة كل رقم، ومقارنة حاسوبين عبر فايربيس',
                  onTap: () {
                    if (requirePermission(context, AppPermissions.manageUsers)) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const StressTestScreen()));
                    }
                  },
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
                SwitchListTile(
                  secondary: const Icon(Icons.bolt_rounded, color: Colors.deepPurple),
                  title: const Text('تسريع البحث (الذاكرة المؤقتة)'),
                  subtitle: const Text('يحفظ علاقات مواد الفاتورة الحالية في الذاكرة، فلا يتأخر البحث أثناء الكتابة'),
                  value: _enableSmartSearchRamCache,
                  activeThumbColor: Colors.deepPurple,
                  onChanged: (v) => setState(() => _enableSmartSearchRamCache = v),
                ),
                const Divider(height: 1),
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
            ]),
          ),
        ],
      ),
    ));
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

    if (confirmed != true || !mounted) return;

    // عرض مؤشر التقدم
    LoadingDialog.show(
      context,
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
          debugPrint('🧠 $message ($current/$total)');
        },
      );

      LoadingDialog.hide();

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
      LoadingDialog.hide();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التدريب: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🧠 دالة عرض إحصائيات البحث الذكي
  Future<void> _showSmartSearchStats() async {
    LoadingDialog.show(
      context,
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

      LoadingDialog.hide();

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
      LoadingDialog.hide();
      if (mounted) {
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
    LoadingDialog.show(
      context,
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
      
      LoadingDialog.hide();
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => _BrandsManagementDialog(brands: brands),
      );
      
      // إعادة تحميل الماركات بعد الإغلاق
      await smart_search.SmartSearchService.instance.loadAutoDiscoveredBrands();
      
    } catch (e) {
      LoadingDialog.hide();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🛡️ دالة الفحص الشامل
  Future<void> _runFullIntegrityCheck() async {
    LoadingDialog.show(
      context,
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
      
      LoadingDialog.hide();
      
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
                      issueText = 'الرصيد المسجل (${NumberFormat('#,##0', 'en').format(r.recordedBalance)}) ≠ المحسوب (${NumberFormat('#,##0', 'en').format(r.calculatedBalance)})';
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
                                '📄 فاتورة #${inv.invoiceId}: فرق ${NumberFormat('#,##0', 'en').format(inv.difference)} دينار',
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
      LoadingDialog.hide();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }



  // 🛡️ دالة عرض الملخص المالي
  Future<void> _showFinancialSummary() async {
    LoadingDialog.show(
      context,
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
      
      LoadingDialog.hide();
      
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
      LoadingDialog.hide();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 📄 دالة مشاركة كشوفات حسابات جميع العملاء
  Future<void> _shareAllAccountStatements() async {
    LoadingDialog.show(
      context,
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
        LoadingDialog.hide();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يوجد عملاء في النظام'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      // دالة لجلب معاملات العميل وتحويلها إلى AccountStatementItem
      Future<List<AccountStatementItem>> getCustomerTransactionsForStatement(int customerId) async {
        return await db.getAccountStatementItems(customerId);
      }

      // إنشاء ملف PDF
      final pdfBytes = await pdfService.generateAllCustomersAccountStatements(
        customers: customers,
        getCustomerTransactions: getCustomerTransactionsForStatement,
      );

      LoadingDialog.hide();

      // حفظ الملف
      final now = DateTime.now();
      final fileName = 'كشوفات_الحسابات_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';
      
      if (!kIsWeb && Platform.isWindows) {
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
      } else if (kIsWeb) {
        // 🌐 الويب: تنزيل مباشر عبر المتصفح (لا مجلدات مؤقتة)
        await _downloadBytesOnWeb(pdfBytes, fileName);
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
      LoadingDialog.hide();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء كشوفات الحساب: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 🌐 تنزيل بايتات ملف في المتصفح
  Future<void> _downloadBytesOnWeb(Uint8List bytes, String fileName) async {
    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName,
    );
  }
  // 📈 دالة تدريب التسعيرة التلقائي
  /// 🔧 «إصلاح إحصائيات التسعير»: يعيد إنشاء الـ Views التي يقرأ منها محرك التسعير.
  /// (كان اسمه «تدريب» مع انتظار مصطنع لثانيتين؛ لا يوجد تدريب فعلي — الـ Views
  /// تُحسب لحظياً من الفواتير. الفائدة الحقيقية: إصلاحها إن كانت مفقودة أو تالفة.)
  Future<void> _trainPricingModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ErpDialog(
        title: 'إصلاح إحصائيات التسعير',
        icon: Icons.build_circle_outlined,
        color: const Color(0xFFEA580C),
        width: 460,
        content: const SetBanner(
          'يعيد إنشاء جداول الإحصاء (Views) التي يقترح منها المحرك الأسعار. لا يغيّر أي فاتورة أو سعر. '
          'الإحصاءات نفسها تتحدّث تلقائياً مع كل فاتورة — هذا الإجراء للإصلاح فقط.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('إصلاح الآن'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    LoadingDialog.show(
      context,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جارٍ إصلاح إحصائيات التسعير...'),
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

      LoadingDialog.hide(); // إغلاق مربع الحوار
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم إصلاح إحصائيات التسعير'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      LoadingDialog.hide(); // إغلاق مربع الحوار
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ تعذّر إصلاح الإحصائيات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// حقل نسبة مئوية ببطاقة: عنوان + شرح + حقل + أزرار سريعة.
  Widget _percentTile({
    required TextEditingController controller,
    required IconData icon,
    required Color color,
    required String title,
    required String hint,
    required String help,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1E293B))),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color),
              decoration: InputDecoration(hintText: hint, suffixText: '%', isDense: true),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(help, style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.5)),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, v, _) {
            final current = double.tryParse(v.text.trim());
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in const [5, 10, 15, 20, 25, 30])
                ChoiceChip(
                  label: Text('$p%'),
                  selected: current == p.toDouble(),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selectedColor: color.withValues(alpha: 0.14),
                  side: BorderSide(color: current == p.toDouble() ? color : const Color(0xFFE6EBF2)),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: current == p.toDouble() ? color : const Color(0xFF1E293B),
                  ),
                  onSelected: (_) => controller.text = '$p',
                ),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _buildPricingModeSelector() {
    // (كان عرض البطاقة يُحسب من عرض الشاشة كاملة فيخرج عن عرض البطاقة الفعلي
    // داخل تخطيط الإعدادات — الآن من عرض المكان المتاح.)
    // أنماط التسعير كلها كما في debt_book (نفس الأرقام المحفوظة)
    const modes = <(int, String, String, IconData)>[
      (99, 'ذكي', 'يوازن آخر الأسعار وتكرارها واتجاهها وسعر الزبون المعتاد', Icons.psychology_rounded),
      (0, 'مطفأ', 'أسعار المادة كما أُدخلت، حسب نوع الفاتورة (مفرد، جملة…) — بلا اقتراح', Icons.block_rounded),
      (1, 'آخر سعر', 'آخر سعر بيعت به المادة بهذه الوحدة', Icons.history_rounded),
      (3, 'متوسط آخر 3', 'متوسط آخر ثلاث عمليات بيع', Icons.functions_rounded),
      (5, 'متوسط آخر 5', 'متوسط آخر خمس عمليات بيع', Icons.functions_rounded),
      (11, 'متوسط آخر شهر', 'متوسط أسعار البيع خلال 30 يوماً', Icons.calendar_view_month_rounded),
      (12, 'متوسط آخر شهرين', 'متوسط أسعار البيع خلال 60 يوماً', Icons.calendar_view_month_rounded),
      (13, 'متوسط آخر 3 أشهر', 'متوسط أسعار البيع خلال 90 يوماً', Icons.calendar_view_month_rounded),
      (21, 'الأكثر تكراراً — شهر', 'السعر الأكثر تكراراً خلال 30 يوماً', Icons.trending_up_rounded),
      (22, 'الأكثر تكراراً — شهرين', 'السعر الأكثر تكراراً خلال 60 يوماً', Icons.trending_up_rounded),
      (23, 'الأكثر تكراراً — 3 أشهر', 'السعر الأكثر تكراراً خلال 90 يوماً', Icons.trending_up_rounded),
      (101, 'شخصي — بالتكلفة', 'كلفة اليوم + مبلغ الربح من آخر بيع لهذا الزبون (أو للسوق)', Icons.person_pin_rounded),
      (102, 'شخصي — بالنسبة', 'كلفة اليوم × نسبة الربح من آخر بيع لهذا الزبون (أو للسوق)', Icons.percent_rounded),
      (103, 'شخصي — هايبرد', 'متوسط الطريقتين: مبلغ الربح ونسبته', Icons.bolt_rounded),
    ];
    const c = Color(0xFFEA580C);
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 640 ? 4 : (box.maxWidth >= 360 ? 2 : 1);
      final w = (box.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final m in modes)
            SizedBox(
              width: w,
              child: Builder(builder: (context) {
                final selected = _pricingMode == m.$1;
                return Material(
                  color: selected ? c.withValues(alpha: 0.07) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: selected ? c : const Color(0xFFE6EBF2), width: selected ? 1.6 : 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _pricingMode = m.$1),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: selected ? c : c.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(m.$4, size: 19, color: selected ? Colors.white : c),
                          ),
                          const Spacer(),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            opacity: selected ? 1 : 0,
                            child: const Icon(Icons.check_circle_rounded, size: 19, color: c),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Text(m.$2,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: selected ? c : const Color(0xFF1E293B),
                            )),
                        const SizedBox(height: 2),
                        Text(m.$3,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.4)),
                      ]),
                    ),
                  ),
                );
              }),
            ),
        ],
      );
    });
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
  static const _teal = Color(0xFF0F766E);

  late List<Map<String, dynamic>> _brands;
  final TextEditingController _newBrandController = TextEditingController();
  bool _isLoading = false;
  String _searchQuery = '';

  /// 0 = الكل، 1 = يدوية، 2 = مكتشفة
  int _filter = 0;

  /// رسالة داخل النافذة (الرسائل السريعة كانت تظهر خلف النافذة فلا تُرى).
  (bool ok, String msg)? _notice;

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

  static bool _isManual(Map<String, dynamic> b) => ((b['count'] as num?)?.toInt() ?? 0) >= 999;

  List<Map<String, dynamic>> get _filteredBrands {
    final q = _searchQuery.trim().toLowerCase();
    return _brands.where((b) {
      if (_filter == 1 && !_isManual(b)) return false;
      if (_filter == 2 && _isManual(b)) return false;
      return q.isEmpty || (b['brand'] as String).toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _addBrand() async {
    final brandName = _newBrandController.text.trim();
    if (brandName.isEmpty) {
      setState(() => _notice = (false, 'أدخل اسم الماركة'));
      return;
    }

    final exists = _brands.any((b) => (b['brand'] as String).toLowerCase() == brandName.toLowerCase());
    if (exists) {
      setState(() => _notice = (false, 'الماركة «$brandName» موجودة بالفعل'));
      return;
    }

    setState(() {
      _isLoading = true;
      _notice = null;
    });

    try {
      await smart_search.SmartSearchService.instance.addManualBrand(brandName);
      if (!mounted) return;
      setState(() {
        _brands.insert(0, {
          'brand': brandName,
          'count': 999,
          'created_at': DateTime.now().toIso8601String(),
        });
        _newBrandController.clear();
        _isLoading = false;
        _notice = (true, 'تمت إضافة الماركة: $brandName');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _notice = (false, 'خطأ: $e');
      });
    }
  }

  Future<void> _deleteBrand(String brand) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ErpDialog(
        title: 'حذف الماركة',
        subtitle: brand,
        icon: Icons.label_off_rounded,
        color: const Color(0xFFB91C1C),
        width: 420,
        content: const SetBanner(
          'ستُحذف الماركة من قائمة البحث الذكي. المواد نفسها لا تُحذف.',
          kind: SetBannerKind.warn,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            label: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isLoading = true;
      _notice = null;
    });

    try {
      await smart_search.SmartSearchService.instance.deleteBrand(brand);
      if (!mounted) return;
      setState(() {
        _brands.removeWhere((b) => b['brand'] == brand);
        _isLoading = false;
        _notice = (true, 'تم حذف الماركة: $brand');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _notice = (false, 'خطأ: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredBrands;
    final manualCount = _brands.where(_isManual).length;
    final autoCount = _brands.length - manualCount;

    Widget filterChip(int value, String label, int count) => ChoiceChip(
          label: Text('$label ($count)'),
          selected: _filter == value,
          showCheckmark: false,
          selectedColor: _teal.withValues(alpha: 0.12),
          side: BorderSide(color: _filter == value ? _teal : const Color(0xFFE6EBF2)),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: _filter == value ? _teal : const Color(0xFF1E293B),
          ),
          onSelected: (_) => setState(() => _filter = value),
        );

    return ErpDialog(
      title: 'إدارة الماركات',
      subtitle: '${_brands.length} ماركة يتعرّف عليها البحث الذكي',
      icon: Icons.sell_rounded,
      color: _teal,
      width: 620,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _newBrandController,
                enabled: !_isLoading,
                decoration: const InputDecoration(
                  labelText: 'ماركة جديدة',
                  hintText: 'مثال: Schneider',
                  prefixIcon: Icon(Icons.add_rounded),
                ),
                onSubmitted: (_) => _addBrand(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _teal, minimumSize: const Size(0, 46)),
              onPressed: _isLoading ? null : _addBrand,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('إضافة'),
            ),
          ]),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _notice == null
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(_notice),
                    padding: const EdgeInsets.only(top: 10),
                    child: SetBanner(_notice!.$2, kind: _notice!.$1 ? SetBannerKind.ok : SetBannerKind.warn),
                  ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              hintText: 'بحث في الماركات...',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            filterChip(0, 'الكل', _brands.length),
            filterChip(1, 'يدوية', manualCount),
            filterChip(2, 'مكتشفة', autoCount),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 340,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.label_off_rounded, size: 44, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            _brands.isEmpty
                                ? 'لا توجد ماركات بعد\nأضف ماركة أو درّب البحث الذكي ليكتشفها من أسماء المواد'
                                : 'لا توجد نتائج',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600], height: 1.6),
                          ),
                        ]),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final brand = list[index];
                          final brandName = brand['brand'] as String;
                          final count = (brand['count'] as num?)?.toInt() ?? 0;
                          final isManual = _isManual(brand);
                          final c = isManual ? _teal : const Color(0xFF64748B);
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE6EBF2)),
                            ),
                            child: Material(type: MaterialType.transparency, child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsetsDirectional.fromSTEB(10, 2, 4, 2),
                              leading: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: c.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(isManual ? Icons.person_add_alt_1_rounded : Icons.auto_awesome_rounded,
                                    size: 17, color: c),
                              ),
                              title: Text(brandName,
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                              subtitle: Text(
                                isManual ? 'مضافة يدوياً' : 'مكتشفة من $count مادة',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                              ),
                              trailing: IconButton(
                                tooltip: 'حذف',
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB91C1C), size: 20),
                                onPressed: _isLoading ? null : () => _deleteBrand(brandName),
                              ),
                            )),
                          );
                        },
                      ),
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تم')),
      ],
    );
  }
}

/// قسم في شاشة الإعدادات: عنوان، أيقونة، وصف قصير، وبطاقاته
class _SettingsSection {
  const _SettingsSection(this.title, this.icon, this.description, this.cards, {this.keywords = ''});
  final String title;
  final IconData icon;
  final String description;
  final List<Widget> cards;

  /// كلمات إضافية للبحث في الإعدادات (ما لا يظهر في العنوان والوصف).
  final String keywords;

  bool matches(String q) => q.isEmpty || title.contains(q) || description.contains(q) || keywords.contains(q);
}

/// عنصر في قائمة أقسام الإعدادات (المختار بخلفية كحلية وأيقونة بيضاء).
class _SettingsRailItem extends StatefulWidget {
  const _SettingsRailItem({required this.section, required this.selected, required this.color, required this.onTap});
  final _SettingsSection section;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  @override
  State<_SettingsRailItem> createState() => _SettingsRailItemState();
}

class _SettingsRailItemState extends State<_SettingsRailItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final c = widget.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? c.withValues(alpha: 0.08) : (_hover ? const Color(0xFFF5F7FB) : Colors.transparent),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? c.withValues(alpha: 0.25) : Colors.transparent),
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: sel ? c : c.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(widget.section.icon, size: 20, color: sel ? Colors.white : c),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                        color: sel ? c : const Color(0xFF1E293B),
                      )),
                  Text(widget.section.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.35)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
