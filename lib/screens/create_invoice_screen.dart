// screens/create_invoice_screen.dart
// screens/create_invoice_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐 حراسة الويب
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../models/invoice_item.dart';
import '../models/invoice.dart';

import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import '../models/transaction.dart';
import '../models/customer.dart';
import '../models/installer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/printing_service.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';
import '../widgets/app_side_nav.dart';
import 'package:path_provider/path_provider.dart' as pp;
import '../services/invoice_pdf_service.dart';
import '../services/smart_pricing_service.dart';
import '../widgets/formatters.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/pdf_service.dart';
import 'package:alnaser/services/printing_service_factory.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:flutter/scheduler.dart';
import '../services/pdf_header.dart';
import '../models/invoice_adjustment.dart';
// removed duplicate imports
import 'invoice_actions.dart';
import 'invoice_history_screen.dart';
import '../services/password_service.dart'; // Added for password protection
import '../utils/money_calculator.dart'; // Added for profit calculation fix
import '../services/smart_search/smart_search.dart'; // 🧠 البحث الذكي
import '../services/auth_service.dart'; // 👤 User authentication
import '../services/logo_service.dart'; // 🖼️ Custom logo loading
import '../utils/number_formatter.dart'; // 🔢 Number formatting
import '../erp/erp_common.dart' show PeriodLock, askNumber;
import '../erp/sales/invoice_side_panel.dart';

// Helper: format product ID - show raw value without zero-padding
String formatProductId5(int? id) {
  if (id == null) return '';
  return id.toString();
}

// تعريف EditableInvoiceItemRow موجود هنا (أو تأكد من وجوده قبل استخدامه في ListView)
// إذا كان التعريف موجود بالفعل، لا داعي لأي تعديل إضافي هنا.
// إذا لم يكن موجودًا، أضف الكود الذي تم إنشاؤه في الخطوة السابقة هنا.

class CreateInvoiceScreen extends StatefulWidget {
  final Invoice? existingInvoice;
  final bool isViewOnly;
  final DebtTransaction? relatedDebtTransaction;
  // إذا كانت غير null فهذا يعني فتح الشاشة بوضع تسوية لفاتورة محفوظة
  final Invoice? settlementForInvoice;

  const CreateInvoiceScreen({
    super.key,
    this.existingInvoice,
    this.isViewOnly = false,
    this.relatedDebtTransaction,
    this.settlementForInvoice,
  });

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> with InvoiceActionsMixin {
  final formKey = GlobalKey<FormState>();
  final customerNameController = TextEditingController();
  final customerPhoneController = TextEditingController();
  final customerAddressController = TextEditingController();
  final installerNameController = TextEditingController();

  AppSettings? _appSettings;

  
  final _productSearchController = TextEditingController();
  final _quantityController = TextEditingController();
  final FocusNode _quantityFocusNode = FocusNode(); // FocusNode لحقل الكمية
  final _itemsController = TextEditingController();
  final _totalAmountController = TextEditingController();
  double? _selectedPriceLevel;
  DateTime selectedDate = DateTime.now();
  bool _useLargeUnit = false;
  String paymentType = 'نقد';
  final paidAmountController = TextEditingController();
  double discount = 0.0;
  final discountController = TextEditingController();
  int _unitSelection = 0; // 0 لـ "قطعة"، 1 لـ "كرتون/باكيت"

  // 🔧 متغيرات اختيار الوحدة في شريط الإدخال
  List<String> currentUnitOptions = ['قطعة'];
  String selectedUnitForItem = 'قطعة';
  List<Map<String, dynamic>> _currentUnitHierarchy = [];

  final _priceController = TextEditingController();
  final _itemSearchFocusNode = FocusNode();
  final _priceFocusNode = FocusNode(); // 🔧 FocusNode لحقل السعر
  final GlobalKey _entryBarUnitDropdownKey = GlobalKey(); // 🔧 مفتاح لقائمة الوحدات في شريط البحث



  String formatNumber(num value, {bool forceDecimal = false}) {
    if (value == 0 && !forceDecimal) return '0';
    return NumberFormatter.format(value, forceDecimal: forceDecimal);
  }
  
  double _adHocProfitPercentage = 10.0;
  bool _allowNegativeStock = false;
  bool _isEntryLocked = false; // 🔒 قفل حقول الإدخال عند نفاد المخزون
  
  Future<void> _loadProfitSettings() async {
    try {
      final settings = await SettingsManager.getAppSettings();
      if (mounted) {
        setState(() {
          _appSettings = settings;
          _adHocProfitPercentage = settings.defaultAdHocProfitPercentage;
          _allowNegativeStock = settings.allowNegativeStock;
        });
        // Recalculate profit with new percentage
        _calculateProfit();
      }
    } catch (e) {
      print('Error loading profit settings: $e');
    }
  }
  


  // kept unused helper removed; global formatProductId5 is used instead

  List<Product> _searchResults = [];
  Product? _selectedProduct;
  List<InvoiceItem> invoiceItems = [];

  final DatabaseService db = DatabaseService();
  final TextEditingController _productIdController = TextEditingController();
  Product? _productIdSuggestion;
  PrinterDevice? selectedPrinter;
  late final PrintingService printingService;
  Invoice? invoiceToManage;

  // إضافة متغيرات للحفظ التلقائي
  final storage = const FlutterSecureStorage();
  bool savedOrSuspended = false;
  Timer? debounceTimer;
  Timer? liveDebtTimer;
  Timer? _invoiceLockHeartbeat;
  
  // متغير لتتبع التغييرات غير المحفوظة
  bool hasUnsavedChanges = false;
  
  // متغير لمنع الحفظ المزدوج
  bool isSaving = false;

  // Profit Display State
  bool _isProfitVisible = false;
  
  // التمرير التلقائي
  final ScrollController _scrollController = ScrollController();
  bool _autoScrollEnabled = true; // سيتم تحميله من الإعدادات
  double _currentInvoiceProfit = 0.0;

  void _calculateProfit() {
    double totalProfit = 0.0;
    
    // Create a map of products for faster lookup
    final Map<String, Product> productMap = {
      for (var p in (_allProductsForUnits ?? [])) p.name: p
    };

    for (var item in invoiceItems) {
      if (!_isInvoiceItemComplete(item)) continue;
      
      final double sellingPrice = item.appliedPrice;
      // Priority 1: Actual Cost Price (if specific batch/item cost is set)
      final double? acp = item.actualCostPrice;
      // Priority 4 (Fallback): Base Cost Price
      final double itemBaseCost = item.costPrice ?? 0.0;
      
      final String saleType = item.saleType ?? '';
      final double qi = item.quantityIndividual ?? 0.0;
      final double ql = item.quantityLargeUnit ?? 0.0;
      final double uilu = item.unitsInLargeUnit ?? 0.0;
      
      // Resolve product data
      final Product? product = productMap[item.productName];
      final String productUnit = product?.unit ?? '';
      final double lengthPerUnit = product?.lengthPerUnit ?? 1.0;
      final double productBaseCost = product?.costPrice ?? 0.0;
      final Map<String, double> unitCosts = product?.getUnitCostsMap() ?? {};

      final bool soldAsLargeUnit = ql > 0;
      final double saleUnitsCount = soldAsLargeUnit ? ql : qi;

      double costPerSaleUnit;
      
      if (acp != null && acp > 0) {
        // Priority 1: Use actual cost price if available
        costPerSaleUnit = acp;
      } else if (soldAsLargeUnit) {
        // Priority 2 & 3: Handle large units (Carton, Roll, etc.)
        
        // Check if specific cost exists for this sale type (e.g. cost of 'Carton')
        if (unitCosts.containsKey(saleType)) {
           costPerSaleUnit = unitCosts[saleType]!;
        } else if (productUnit == 'meter' && saleType == 'لفة') {
           // Special case for Rolls: Cost = Base Cost * Length
           costPerSaleUnit = productBaseCost * lengthPerUnit;
        } else {
           // Default: Cost = Base Cost * Units in Large Unit
           costPerSaleUnit = productBaseCost * (uilu > 0 ? uilu : 1.0);
        }
      } else {
        // Priority 4: Selling in base units (Piece, Meter)
        // Use item's stored cost if available, otherwise product's base cost
        costPerSaleUnit = itemBaseCost > 0 ? itemBaseCost : productBaseCost;
      }


      // 🔧 استخدام نسبة الربح المحددة في الإعدادات
      if (costPerSaleUnit <= 0 && sellingPrice > 0) {
        costPerSaleUnit = MoneyCalculator.getEffectiveCost(
          0, 
          sellingPrice, 
          profitMargin: _adHocProfitPercentage / 100.0
        );
      }

      final double lineAmount = sellingPrice * saleUnitsCount;
      final double lineCostTotal = costPerSaleUnit * saleUnitsCount;
      
      totalProfit += (lineAmount - lineCostTotal);
    }
    
    // Subtract discount from profit
    _currentInvoiceProfit = totalProfit - discount;
  }

  Future<void> _toggleProfitVisibility() async {
    if (_isProfitVisible) {
      setState(() {
        _isProfitVisible = false;
      });
    } else {
      // Show password dialog
      final controller = TextEditingController();
      final shouldShow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('أدخل رمز المرور'),
          content: TextField(
            controller: controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(hintText: '****'),
            onSubmitted: (value) async {
              if (await PasswordService().verifyPassword(value)) {
                Navigator.pop(context, true);
              } else {
                Navigator.pop(context, false);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                if (await PasswordService().verifyPassword(controller.text)) {
                  Navigator.pop(context, true);
                } else {
                  Navigator.pop(context, false);
                }
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      );

      if (shouldShow == true) {
        _calculateProfit();
        setState(() {
          _isProfitVisible = true;
        });
      } else if (shouldShow == false) { // Explicit check for false (wrong password or cancel)
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رمز المرور غير صحيح')),
        );
      }
    }
  }
  
  // دالة لإظهار Dialog الحفظ عند الرجوع
  Future<bool> _showSaveDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('تعديلات غير محفوظة'),
          content: const Text('هل تريد حفظ التعديلات قبل الخروج؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false), // تجاهل
              child: const Text('تجاهل'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true), // حفظ
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
    return result ?? false; // إذا أغلقت Dialog، نعتبرها تجاهل
  }
  
  // دالة لاعتراض زر الرجوع
  Future<bool> _onWillPop() async {
    // للفواتير الجديدة: حفظ مؤقت قبل الخروج
    if (invoiceToManage == null && !isViewOnly && !savedOrSuspended) {
      // حفظ البيانات مؤقتاً قبل الخروج
      await _autoSave();
      return true;
    }
    
    // إذا كانت في وضع العرض فقط، اخرج مباشرة
    if (isViewOnly) {
      return true;
    }
    
    // إذا لا توجد تغييرات غير محفوظة، اخرج مباشرة
    if (!hasUnsavedChanges) {
      return true;
    }
    
    // إظهار Dialog الحفظ
    final shouldSave = await _showSaveDialog();
    
    if (shouldSave) {
      // حفظ الفاتورة
      final savedInvoice = await saveInvoice();
      if (savedInvoice != null) {
        // تم الحفظ بنجاح، hasUnsavedChanges تم إعادة تعيينه في _saveInvoice
        return true; // اخرج
      } else {
        return false; // فشل الحفظ، ابق في الشاشة
      }
    } else {
      // تجاهل التعديلات - إعادة تحميل البيانات الأصلية
      await _loadInvoiceItems();
      hasUnsavedChanges = false;
      return true; // اخرج
    }
  }

  bool isViewOnly = false;

  // تسوية الفاتورة - حالة الواجهة
  bool settlementPanelVisible = false; // عند اختيار "بند"
  bool _settlementIsDebit = true; // true = إضافة (debit), false = حذف (credit)
  final List<InvoiceItem> _settlementItems = [];
  String _settlementPaymentType = 'نقد';
  final TextEditingController _settleNameCtrl = TextEditingController();
  final TextEditingController _settleIdCtrl = TextEditingController();
  final TextEditingController _settleQtyCtrl = TextEditingController();
  final TextEditingController _settlePriceCtrl = TextEditingController();
  final TextEditingController _settleUnitCtrl = TextEditingController();
  Product? _settleSelectedProduct;
  String _settleSelectedSaleType = 'قطعة'; // نوع البيع المحدد في التسوية
  
  // Controllers للـ Autocomplete في لوحة التسوية
  TextEditingController? _settleIdController;
  TextEditingController? _settleNameController;
  
  // معلومات التسويات
  List<InvoiceAdjustment> _invoiceAdjustments = [];
  double _totalSettlementAmount = 0.0;
  
  // جلب معلومات التسويات
  Future<void> _loadSettlementInfo() async {
    if (invoiceToManage?.id != null) {
      try {
        final adjustments = await db.getInvoiceAdjustments(invoiceToManage!.id!);
        setState(() {
          _invoiceAdjustments = adjustments;
          _totalSettlementAmount = adjustments.fold(0.0, (sum, adj) {
            return sum + (adj.type == 'debit' ? adj.amountDelta : -adj.amountDelta);
          });
        });
      } catch (e) {
        print('Error loading settlement info: $e');
      }
    }
  }
  
  // 🧠 تهيئة سياق البحث الذكي
  void _initSmartSearchContext() async {
    // 🆕 تحميل الماركات المكتشفة تلقائياً أولاً
    await SmartSearchService.instance.loadAutoDiscoveredBrands();
    
    // بدء جلسة جديدة
    SmartSearchService.instance.startNewSession(
      customerName: invoiceToManage?.customerName,
      customerId: invoiceToManage?.customerId,
      installerName: invoiceToManage?.installerName,
    );
    
    // إذا كانت فاتورة موجودة، أضف المنتجات الحالية للسياق
    if (invoiceToManage != null && invoiceItems.isNotEmpty) {
      for (final item in invoiceItems) {
        if (item.productName.isNotEmpty) {
          SmartSearchService.instance.addProductToSession(
            item.productId,
            item.productName,
          );
        }
      }
    }
  }

  // تحميل الإعدادات الافتراضية للفاتورة
  Future<void> _loadDefaultSettings() async {
    try {
      final settings = await SettingsManager.getAppSettings();
      setState(() {
        _autoScrollEnabled = settings.autoScrollInvoice;
      });
    } catch (e) {
      print('Error loading default settings: $e');
    }
  }
  

  
  // دالة التمرير التلقائي للأسفل
  void _scrollToBottom() {
    if (!_autoScrollEnabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  final FocusNode _searchFocusNode = FocusNode(); // FocusNode جديد لحقل البحث
  bool suppressSearch = false; // لمنع البحث التلقائي عند اختيار منتج
  bool quantityAutofocus = false; // للتحكم في autofocus لحقل الكمية

  // أضف متغير نوع القائمة (يظل موجوداً ولكن بدون واجهة مستخدم لتغييره)
  String _selectedListType = 'مفرد';
  final List<String> _listTypes = ['مفرد', 'مفرد 2', 'منزل', 'جملة', 'جملة 2', 'أخرى'];


  // متغير للتحكم في السعر المخصص
  bool isCustomPrice = false;

  List<Product>? _allProductsForUnits;

  late TextEditingController loadingFeeController;

  List<LineItemFocusNodes> focusNodesList = [];

  void _handleChangeProductId(String value) {
    final v = value.trim();
    if (v.isEmpty) {
      setState(() {
        _productIdSuggestion = null;
      });
      return;
    }
    final id = int.tryParse(v);
    if (id == null) {
      setState(() {
        _productIdSuggestion = null;
      });
      return;
    }
    // بحث مباشر سريع
    db.getProductById(id).then((p) {
      if (!mounted) return;
      setState(() {
        _productIdSuggestion = p;
      });
    });
  }

  Future<void> _handleSubmitProductId(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final id = int.tryParse(trimmed);
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال ID صحيح')));
      return;
    }
    final product = await db.getProductById(id);
    if (product == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم يتم العثور على صنف بهذا المعرّف')));
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _productIdController.clear();

    double? newPriceLevel;
    switch (_selectedListType) {
      case 'مفرد':
        newPriceLevel = product.price1;
        break;
      case 'مفرد 2':
        newPriceLevel = product.price2;
        break;
      case 'منزل':
        newPriceLevel = product.price3;
        break;
      case 'جملة':
        newPriceLevel = product.price4;
        break;
      case 'جملة 2':
        newPriceLevel = product.price5;
        break;
      case 'أخرى':
        newPriceLevel = product.price6;
        break;
      default:
        newPriceLevel = product.price1;
    }
    newPriceLevel ??= product.unitPrice;

    // لا نضيف مباشرة. نختار المنتج ونظهر خيارات الوحدة والكمية
    // توحيد مسار التهيئة مع البحث الذكي لضمان إعداد الوحدات وأنواع البيع والأسعار بشكل صحيح
    _onProductSelected(product);
    setState(() {
      _selectedPriceLevel = newPriceLevel;
      _productIdSuggestion = null;
    });
  }

  @override
  void initState() {
    super.initState();
    try {
      printingService = getPlatformPrintingService();
      invoiceToManage = widget.existingInvoice;
      isViewOnly = widget.isViewOnly;
      // تفعيل وضع التسوية: افتح واجهة إدخال أصناف جديدة، لكن اربطها بالفاتورة الأساسية
      if (widget.settlementForInvoice != null) {
        // في وضع التسوية: اجعل الشاشة قابلة للإدخال، ولا تعدّل الأصناف الأصلية
        isViewOnly = false;
        invoiceToManage = widget.settlementForInvoice; // للربط ولأخذ العميل/التاريخ إن لزم
        // نظف أي بيانات إدخال قديمة وابدأ بقائمة فارغة لتسوية جديدة
        invoiceItems.clear();
        _totalAmountController.text = '0';
        // أضف صف فارغ كبداية
        invoiceItems.add(InvoiceItem(
          invoiceId: 0,
          productName: '',
          unit: '',
          unitPrice: 0.0,
          appliedPrice: 0.0,
          itemTotal: 0.0,
          uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
        ));
      }
      loadingFeeController = TextEditingController();
      _loadAutoSavedData();
      _loadSettlementInfo(); // جلب معلومات التسويات
      
      // تحميل إعدادات النقاط الافتراضية (فقط للفواتير الجديدة)
      if (widget.existingInvoice == null) {
         _loadDefaultSettings(); 
      }
      
      // 🧠 تهيئة سياق البحث الذكي
      _initSmartSearchContext();
      
      // 💰 تحميل إعدادات الأرباح
      _loadProfitSettings();
      

      
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          _allProductsForUnits = await db.getAllProducts();
          setState(() {});
        } catch (e) {
          print('Error loading products: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error loading products. Please restart app.')),
            );
          }
        }
      });
      
      // 🔒 [Locking System] Invoice Lock Logic
      // If editing an existing invoice, try to acquire lock immediately
      if (widget.existingInvoice != null && !widget.isViewOnly) {
         WidgetsBinding.instance.addPostFrameCallback((_) async {
           final lockResult = await db.lockingService.acquireLock(
             resourceType: 'invoice', 
             resourceId: widget.existingInvoice!.id!
           );
           
           if (!lockResult.success && mounted) {
             // ⛔ Locked by another user
             await showDialog(
               context: context,
               barrierDismissible: false,
               builder: (ctx) => AlertDialog(
                 title: const Text('⚠️ الفاتورة قيد التعديل'),
                 content: Text(
                   'عذراً، هذه الفاتورة مفتوحة حالياً من قبل:\n\n👤 ${lockResult.lockedBy ?? "مستخدم آخر"}\n\nلا يمكن تعديلها في نفس الوقت لمنع تضارب البيانات.'
                 ),
                 actions: [
                   TextButton(
                     onPressed: () {
                        Navigator.of(ctx).pop(); // Close Dialog
                        Navigator.of(context).pop(); // Exit Screen
                     },
                     child: const Text('حسناً، خروج'),
                   )
                 ],
               )
             );
           } else {
             // ✅ Lock acquired - Start heartbeat
             _startInvoiceLockHeartbeat();
           }
         });
      }


      // إضافة استماع للتغيرات في الحقول
      customerNameController.addListener(_onFieldChanged);
      customerNameController.addListener(_onCustomerChanged); // 🧠 تحديث سياق البحث الذكي
      customerPhoneController.addListener(_onFieldChanged);
      customerAddressController.addListener(_onFieldChanged);
      installerNameController.addListener(_onFieldChanged);
      installerNameController.addListener(_onInstallerChanged); // 🧠 تحديث سياق البحث الذكي
      paidAmountController.addListener(_onFieldChanged);
      discountController.addListener(_onFieldChanged);
      discountController.addListener(_onDiscountChanged);

      if (invoiceToManage != null) {
        customerNameController.text = invoiceToManage!.customerName;
        customerPhoneController.text = invoiceToManage!.customerPhone ?? '';
        customerAddressController.text =
            invoiceToManage!.customerAddress ?? '';
        installerNameController.text = invoiceToManage!.installerName ?? '';
        selectedDate = invoiceToManage!.invoiceDate;
        paymentType = invoiceToManage!.paymentType;
        _totalAmountController.text = formatNumber(invoiceToManage!.totalAmount);
        paidAmountController.text =
            formatNumber(invoiceToManage!.amountPaidOnInvoice);
        discount = invoiceToManage!.discount;
        discountController.text = formatNumber(discount);
        // تهيئة قيمة أجور التحميل من الفاتورة الحالية
        try {
          loadingFeeController.text = formatNumber(invoiceToManage!.loadingFee);
        } catch (_) {
          loadingFeeController.text = invoiceToManage!.loadingFee.toString();
        }
        


        _loadInvoiceItems();
      } else {
        _totalAmountController.text = '0';
      }
      // تهيئة FocusNode
      _quantityFocusNode.addListener(_onFieldChanged);
      // إضافة مستمع لحقل البحث
      _productSearchController.addListener(() {
        if (suppressSearch) {
          suppressSearch = false;
          return;
        }
        if (_productSearchController.text.isNotEmpty) {
          _searchProducts(_productSearchController.text);
        }
        if (_productSearchController.text.isEmpty) {
          setState(() {
            _searchResults = [];
            _selectedProduct = null;
          });
        }
      });
    } catch (e) {
      print('Error in initState: $e');
    }
    if (invoiceItems.isEmpty) {
      invoiceItems.add(InvoiceItem(
        invoiceId: 0,
        productName: '',
        unit: '',
        unitPrice: 0.0,
        appliedPrice: 0.0,
        itemTotal: 0.0,
        uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
      ));
    }
  }

  // 🔹 Start Heartbeat Method (Locking)
  void _startInvoiceLockHeartbeat() {
    _invoiceLockHeartbeat?.cancel();
    _invoiceLockHeartbeat = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (invoiceToManage == null || !mounted) {
          timer.cancel();
          return;
      }
      await db.lockingService.keepAlive(
        resourceType: 'invoice', 
        resourceId: invoiceToManage!.id!
      );
    });
  }


  // تحميل البيانات المحفوظة تلقائياً
  Future<void> _loadAutoSavedData() async {
    try {
      if (isViewOnly || widget.existingInvoice != null) {
        return;
      }

      final tempData = await storage.read(key: 'temp_invoice_data');
      if (tempData == null) return;

      final data = jsonDecode(tempData);
      setState(() {
        customerNameController.text = data['customerName'] ?? '';
        customerPhoneController.text = data['customerPhone'] ?? '';
        customerAddressController.text = data['customerAddress'] ?? '';
        installerNameController.text = data['installerName'] ?? '';

        if (data['selectedDate'] != null) {
          selectedDate = DateTime.parse(data['selectedDate']);
        }

        paymentType = data['paymentType'] ?? 'نقد';
        discount = data['discount'] ?? 0;
        discountController.text = formatNumber(discount);
        paidAmountController.text = data['paidAmount'] ?? '';

        invoiceItems = (data['invoiceItems'] as List<dynamic>).map((item) {
          return InvoiceItem(
            invoiceId: 0,
            productName: item['productName'],
            unit: item['unit'],
            unitPrice: item['unitPrice'],
            costPrice: item['costPrice'] ?? 0,
            quantityIndividual: item['quantityIndividual'],
            quantityLargeUnit: item['quantityLargeUnit'],
            appliedPrice: item['appliedPrice'],
            itemTotal: item['itemTotal'],
            saleType: item['saleType'],
            unitsInLargeUnit: item['unitsInLargeUnit'],
            uniqueId: item['uniqueId'] ?? 'item_${DateTime.now().microsecondsSinceEpoch}',
          );
        }).toList();

        double itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
        _totalAmountController.text = formatNumber(itemsTotal + loadingFee);
        
        // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
        if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
          final newTotal = (itemsTotal + loadingFee) - discount;
          paidAmountController.text = formatNumber(newTotal);
        }
      });
    } catch (e) {
      print('Error loading auto-saved data: $e');
    }
  }

  // حفظ البيانات تلقائياً
  Future<void> _autoSave() async {
    try {
      if (savedOrSuspended || isViewOnly || widget.existingInvoice != null) {
        return;
      }

      final data = {
        'customerName': customerNameController.text,
        'customerPhone': customerPhoneController.text,
        'customerAddress': customerAddressController.text,
        'installerName': installerNameController.text,
        'selectedDate': selectedDate.toIso8601String(),
        'paymentType': paymentType,
        'discount': discount,
        'paidAmount': paidAmountController.text,
        'invoiceItems': invoiceItems
            .map((item) => {
                  'productName': item.productName,
                  'unit': item.unit,
                  'unitPrice': item.unitPrice,
                  'costPrice': item.costPrice,
                  'quantityIndividual': item.quantityIndividual,
                  'quantityLargeUnit': item.quantityLargeUnit,
                  'appliedPrice': item.appliedPrice,
                  'itemTotal': item.itemTotal,
                  'saleType': item.saleType,
                  'unitsInLargeUnit': item.unitsInLargeUnit,
                  'uniqueId': item.uniqueId,
                })
            .toList(),
      };

      await storage.write(key: 'temp_invoice_data', value: jsonEncode(data));
    } catch (e) {
      print('Error in autoSave: $e');
    }
  }

  // حفظ البيانات فوراً (يُستخدم عند الخروج من الشاشة)
  void _saveDataImmediately() {
    try {
      if (savedOrSuspended || isViewOnly || widget.existingInvoice != null) {
        return;
      }

      final data = {
        'customerName': customerNameController.text,
        'customerPhone': customerPhoneController.text,
        'customerAddress': customerAddressController.text,
        'installerName': installerNameController.text,
        'selectedDate': selectedDate.toIso8601String(),
        'paymentType': paymentType,
        'discount': discount,
        'paidAmount': paidAmountController.text,
        'invoiceItems': invoiceItems
            .map((item) => {
                  'productName': item.productName,
                  'unit': item.unit,
                  'unitPrice': item.unitPrice,
                  'costPrice': item.costPrice,
                  'quantityIndividual': item.quantityIndividual,
                  'quantityLargeUnit': item.quantityLargeUnit,
                  'appliedPrice': item.appliedPrice,
                  'itemTotal': item.itemTotal,
                  'saleType': item.saleType,
                  'unitsInLargeUnit': item.unitsInLargeUnit,
                  'uniqueId': item.uniqueId,
                })
            .toList(),
      };

      // حفظ فوري بدون await (fire and forget)
      storage.write(key: 'temp_invoice_data', value: jsonEncode(data));
    } catch (e) {
      print('Error in _saveDataImmediately: $e');
    }
  }

  // معالج تغيير الحقول مع تأخير
  void _onFieldChanged() {
    try {
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      if (debounceTimer?.isActive ?? false) {
        debounceTimer!.cancel();
      }

      debounceTimer = Timer(const Duration(milliseconds: 300), _autoSave);
    } catch (e) {
      print('Error in onFieldChanged: $e');
    }
  }

  // 🧠 معالج تغيير اسم العميل (للبحث الذكي)
  void _onCustomerChanged() {
    SmartSearchService.instance.updateSessionCustomer(
      customerName: customerNameController.text.trim(),
      customerId: null, // سيتم تحديثه عند الحفظ
    );
  }

  // 🧠 معالج تغيير اسم المُركّب (للبحث الذكي)
  void _onInstallerChanged() {
    SmartSearchService.instance.updateSessionInstaller(
      installerNameController.text.trim(),
    );
  }

  // معالج تغيير الخصم
  void _onDiscountChanged() {
    try {
      final discountText = discountController.text.replaceAll(',', '');
      final newDiscount = double.tryParse(discountText) ?? 0.0;
      discount = newDiscount;
      
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
      if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
        final currentTotalAmount = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final newTotal = currentTotalAmount - discount;
        paidAmountController.text = formatNumber(newTotal);
      }
      _calculateProfit(); // Update profit on discount change
      // 🔧 إصلاح: تحديث الواجهة فوراً إذا كان الربح ظاهراً
      if (_isProfitVisible) {
        setState(() {});
      }
      _scheduleLiveDebtSync();
    } catch (e) {
      print('Error in onDiscountChanged: $e');
    }
  }

  Future<void> _loadInvoiceItems() async {
    try {
      if (invoiceToManage != null && invoiceToManage!.id != null) {
        final items = await db.getInvoiceItems(invoiceToManage!.id!);
        
        // تهيئة الـ controllers لكل صنف
        for (var item in items) {
          item.initializeControllers();
        }
        // تهيئة FocusNodes لكل صنف
        focusNodesList.clear();
        for (var _ in items) {
          focusNodesList.add(LineItemFocusNodes());
        }
        setState(() {
          invoiceItems = items;
          double itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
          final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
          _totalAmountController.text = formatNumber(itemsTotal + loadingFee);
        });
        
        _scheduleLiveDebtSync();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل أصناف الفاتورة: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    try {
      // 1. إلغاء المؤقت أولاً لمنع أي عمليات حفظ متأخرة
      debounceTimer?.cancel();

      // 2. إزالة جميع المستمعين لمنع استدعاء logic بعد التخلص من الكائنات
      customerNameController.removeListener(_onFieldChanged);
      customerNameController.removeListener(_onCustomerChanged);
      customerPhoneController.removeListener(_onFieldChanged);
      customerAddressController.removeListener(_onFieldChanged);
      installerNameController.removeListener(_onFieldChanged);
      installerNameController.removeListener(_onInstallerChanged);
      paidAmountController.removeListener(_onFieldChanged);
      discountController.removeListener(_onFieldChanged);
      discountController.removeListener(_onDiscountChanged);
      _quantityFocusNode.removeListener(_onFieldChanged);
      _productSearchController.removeListener(_onFieldChanged);

      // 3. الحفظ الفوري عند إغلاق الشاشة إذا لزم الأمر
      if (!savedOrSuspended &&
          widget.existingInvoice == null &&
          !isViewOnly) {
        _saveDataImmediately();
      }

      // 🔒 [Locking System] Release Locks
      _invoiceLockHeartbeat?.cancel();
      
      // Release Invoice Lock if we held it
      if (invoiceToManage?.id != null && !isViewOnly) {
         db.lockingService.releaseLock(resourceType: 'invoice', resourceId: invoiceToManage!.id!);
      }
      
      // Release Customer Lock if we held it (New Invoice scenario) or generally just cleanup
      if (invoiceToManage?.customerId != null) {
         db.lockingService.releaseLock(resourceType: 'customer', resourceId: invoiceToManage!.customerId!);
      }
      
      // 4. التخلص من المتحكمات (Controllers)
      customerNameController.dispose();
      customerPhoneController.dispose();
      customerAddressController.dispose();
      installerNameController.dispose();

      _productSearchController.dispose();
      _quantityController.dispose();
      _itemsController.dispose();
      _totalAmountController.dispose();
      paidAmountController.dispose();
      discountController.dispose();
      loadingFeeController.dispose();
      _productIdController.dispose();
      
      // 5. التخلص من عقد التركيز (FocusNodes)
      _quantityFocusNode.dispose();
      _searchFocusNode.dispose();
      _scrollController.dispose();

      // 6. التخلص من عقد التركيز لصفوف الفاتورة
      for (final node in focusNodesList) {
        node.dispose();
      }
      focusNodesList.clear();
      
    } catch (e) {
      print('Error in dispose: $e');
    } finally {
      super.dispose();
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        locale: const Locale('ar', 'SA'),
      );
      if (picked != null && picked != selectedDate) {
        // تحديد أن هناك تغييرات غير محفوظة
        if (invoiceToManage != null && !isViewOnly) {
          hasUnsavedChanges = true;
        }
        
        setState(() {
          selectedDate = picked;
          _autoSave(); // حفظ تلقائي عند تغيير التاريخ
        });
      }
    } catch (e) {
      print('Error selecting date: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء اختيار التاريخ: $e')),
        );
      }
    }
  }

  /// دالة البحث عن المنتجات - تستخدم خوارزمية البحث الذكية المتعددة الطبقات
  /// تدعم البحث عن "كوب فنار" لإيجاد "كوب واحد سيه فنار"، "كوب اثنين سيات فنار"، إلخ
  Future<void> _searchProducts(String query) async {
    try {
      if (query.isEmpty) {
        setState(() {
          _searchResults = [];
        });
        return;
      }
      // 🧠 استخدام البحث الذكي مع تمرير قائمة المنتجات الحالية في الفاتورة
      // هذا يضمن دقة التحقق من المنتجات المضافة (حتى لو تم حذفها)
      final currentProductNames = invoiceItems
          .where((item) => item.productName.isNotEmpty)
          .map((item) => item.productName)
          .toList();
      final results = await SmartSearchService.instance.smartSearch(
        query,
        currentInvoiceProductNames: currentProductNames,
      );
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      print('Error searching products: $e');
      setState(() {
        _searchResults = [];
      });
    }
  }

  // دالة لتحديث المبلغ المسدد تلقائيًا إذا كان الدفع نقد
  void _updatePaidAmountIfCash() {
    try {
      if (paymentType == 'نقد') {
        _guardDiscount();
        final itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
        final currentTotalAmount = itemsTotal + loadingFee;
        final total = currentTotalAmount - discount;
        paidAmountController.text =
            formatNumber(total.clamp(0, double.infinity));
      }
    } catch (e) {
      print('Error in updatePaidAmountIfCash: $e');
    }
  }

  // دالة مركزية لحماية الخصم
  void _guardDiscount() {
    try {
      final itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
      final currentTotalAmount = itemsTotal + loadingFee;
      // الحد الأعلى للخصم هو أقل من نصف الإجمالي
      final maxDiscount = (currentTotalAmount / 2) - 1;
      if (discount > maxDiscount) {
        discount = maxDiscount > 0 ? maxDiscount : 0.0;
        discountController.text = formatNumber(discount);
      }
      if (discount < 0) {
        discount = 0.0;
        discountController.text = formatNumber(0);
      }
      
      // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً عند تغيير الخصم
      if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
        final newTotal = currentTotalAmount - discount;
        paidAmountController.text = formatNumber(newTotal);
      }
    } catch (e) {
      print('Error in guardDiscount: $e');
    }
  }

  // --- دالة حساب التكلفة الفعلية بناءً على نوع وحدة البيع (تعامل مع غياب/صفر unit_costs) ---
  // 🔧 Fix: إضافة معامل unitsInLargeUnit للاستخدام كـ fallback
  double _calculateActualCostPrice(Product product, String saleUnit, double quantity, {double? unitsInLargeUnit}) {
    final double baseCost = product.costPrice ?? 0.0;
    // بيع بالوحدة الأساسية
    if ((product.unit == 'piece' && saleUnit == 'قطعة') ||
        (product.unit == 'meter' && saleUnit == 'متر')) {
      return baseCost;
    }

    // جرّب قراءة تكلفة الوحدة المباعة من unit_costs; اعتبر الصفر كأنه غير متوفر
    Map<String, double> unitCosts = const {};
    try { unitCosts = product.getUnitCostsMap(); } catch (_) {}
    final double? stored = unitCosts[saleUnit];
    if (stored != null && stored > 0) {
      return stored;
    }

    // للمتر و"لفة": استخدم طول اللفة عند عدم توفر تكلفة مخزنة
    if (product.unit == 'meter' && saleUnit == 'لفة') {
      final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
      return baseCost * lengthPerUnit;
    }

    // للقطعة مع هرمية: احسب المضاعف التراكمي حتى وحدة البيع المطلوبة
    if (product.unit == 'piece' && product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
      try {
        // 🔧 Robust JSON parsing with fallback
        List<dynamic> hierarchy;
        try {
          hierarchy = jsonDecode(product.unitHierarchy!) as List<dynamic>;
        } catch (_) {
          // Fallback: try with single quote replacement
          hierarchy = jsonDecode(product.unitHierarchy!.replaceAll("'", '"')) as List<dynamic>;
        }
        
        double multiplier = 1.0;
        for (final level in hierarchy) {
          final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
          final double qty = (level['quantity'] is num)
              ? (level['quantity'] as num).toDouble()
              : double.tryParse(level['quantity'].toString()) ?? 1.0;
          multiplier *= qty;
          if (unitName == saleUnit) {
            return baseCost * multiplier;
          }
        }
        // 🔧 Fix: إذا لم نجد الوحدة في الهرمية، استخدم المضاعف المحسوب إذا توفر
        if (multiplier > 1.0) {
          return baseCost * multiplier;
        }
      } catch (e) {
        print('خطأ في حساب التكلفة الهيراركية: $e');
      }
    }

    // 🔧 Fix: للوحدات الكبيرة غير الموجودة في الهرمية، استخدم unitsInLargeUnit كـ fallback
    if (saleUnit != 'قطعة' && saleUnit != 'متر' && unitsInLargeUnit != null && unitsInLargeUnit > 1) {
      return baseCost * unitsInLargeUnit;
    }

    // رجوع آمن
    return baseCost;
  }

  void _addInvoiceItem() {
    try {
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      if (formKey.currentState!.validate() && _selectedProduct != null) {
        final double inputQuantity = safeParseDouble(_quantityController.text) ?? 0.0;
        final double inputPrice = safeParseDouble(_priceController.text) ?? 0.0; // 🔧 المصدر الحقيقي للسعر

        if (inputQuantity <= 0) {
           return;
        }

       // 🔒 التحقق من السعر قبل الإضافة وعرض تحذير
        if (_isEntryPriceBelowCost()) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ تنبيه: تم إضافة الصنف بسعر أقل من التكلفة!', style: TextStyle(fontFamily: 'Cairo')),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
        }

        // 🔧 استخدام السعر المدخل مباشرة من الحقل (لأنه تم تحديثه بالفعل عند اختيار الوحدة)
        double finalAppliedPrice = inputPrice;

        double baseUnitsPerSelectedUnit = 1.0;

        print('🔍 [تشخيص-إضافة-صنف] "${_selectedProduct!.name}" | الوحدة: "$selectedUnitForItem" | الكمية: $inputQuantity | السعر من الحقل: $inputPrice');
        print('    unit="${_selectedProduct!.unit}" | isWeighable=${_selectedProduct!.isWeighable} | unitHierarchy=${_selectedProduct!.unitHierarchy}');

        // --- حساب معامل التحويل (للمخزون فقط) ---
        if (_selectedProduct!.unit == 'piece' && selectedUnitForItem != 'قطعة') {
          // إذا كان هناك تسلسل هرمي للوحدات
          if (_selectedProduct!.unitHierarchy != null && _selectedProduct!.unitHierarchy!.isNotEmpty) {
            try {
              // 🔧 Robust JSON parsing matching row logic
              List<dynamic> hierarchy;
              try {
                hierarchy = jsonDecode(_selectedProduct!.unitHierarchy!);
              } catch (_) {
                hierarchy = jsonDecode(_selectedProduct!.unitHierarchy!.replaceAll("'", '"'));
              }

              for (final level in hierarchy) {
                final unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                final double quantity = (level['quantity'] is num)
                    ? (level['quantity'] as num).toDouble()
                    : double.tryParse(level['quantity'].toString()) ?? 1.0;
                
                // حساب المضاعف التراكمي: نضرب العوامل (كما في الصفوف)
                // ملاحظة: المنطق هنا يفترض أننا نريد الوصول للوحدة المحددة وحساب معاملها بالنسبة للوحدة الأساسية
                if (unitName == selectedUnitForItem) {
                   // في هذه اللحظة، الكمية هي كمية القطع في هذه الوحدة
                   // ولكن إذا كان هناك تسلسل (كرتون يحتوي 10 باكيت، والباكيت يحتوي 12 قطعة)
                   // فالكود الحالي يحتاج لتحسين إذا كان التسلسل معقداً، لكن سنمشي على نفس منطق الصفوف البسيط
                   // الذي يضرب الكميات حتى يجد الوحدة.
                   
                   // انتظر، منطق الصفوف كان يضرب `multiplier *= qty` حتى يجد الوحدة.
                   // سنطبق نفس المنطق هنا:
                   double multiplier = 1.0;
                   for (final l in hierarchy) {
                      final q = (l['quantity'] is num) ? (l['quantity'] as num).toDouble() : double.tryParse(l['quantity'].toString()) ?? 1.0;
                      multiplier *= q;
                      if ((l['unit_name'] ?? l['name']) == selectedUnitForItem) {
                        break;
                      }
                   }
                   baseUnitsPerSelectedUnit = multiplier;
                   break;
                }
              }
            } catch (e) {
              // fallback: استخدام 1.0 في حال الفشل التام
              print('Add item JSON parse error: $e');
              baseUnitsPerSelectedUnit = 1.0;
            }
          }
        } else if (_selectedProduct!.unit == 'meter' && selectedUnitForItem == 'لفة') {
          baseUnitsPerSelectedUnit = _selectedProduct!.lengthPerUnit ?? 1.0;
        } else if (selectedUnitForItem != 'قطعة' && selectedUnitForItem != _selectedProduct!.translatedUnit) {
          print('    ⚠️ [تشخيص-إضافة-صنف] وحدة غير أساسية بلا معامل تحويل! '
              'unit="${_selectedProduct!.unit}" ليست piece/meter → المخزون سيُخصم $inputQuantity فقط (بدل المضاعف)');
        }
        print('    معامل التحويل للمخزون: $baseUnitsPerSelectedUnit');

        final double totalBaseUnitsSold = inputQuantity * baseUnitsPerSelectedUnit;

        // 🔒 التحقق من المخزون
        if (!_allowNegativeStock && (_selectedProduct!.stockQuantity ?? 0) < totalBaseUnitsSold) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ عذراً، الرصيد غير كافٍ! \n'
                  'المطلوب: $totalBaseUnitsSold قطعة، المتاح: ${_selectedProduct!.stockQuantity ?? 0}',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        // 📦 البيع بلا رصيد كافٍ مسموح (إعداد «السماح بالبيع عند نفاذ الكمية»):
        //    نكمل البيع وننبّه — المخزن مشترك والكمية قد تصير سالبة.
        if (_allowNegativeStock &&
            (_selectedProduct!.stockQuantity ?? 0) < totalBaseUnitsSold &&
            mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ تنبيه: الكمية المتاحة ${_selectedProduct!.stockQuantity ?? 0} أقل من '
                'المطلوب $totalBaseUnitsSold — سيصبح المخزون سالباً',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        final double finalItemCostPrice = (_selectedProduct!.costPrice ?? 0) * totalBaseUnitsSold;
        final double finalItemTotal = inputQuantity * finalAppliedPrice;
        
        double? quantityIndividual;
        double? quantityLargeUnit;
        if (selectedUnitForItem == _selectedProduct!.translatedUnit || selectedUnitForItem == 'قطعة' || selectedUnitForItem == 'متر') {
          quantityIndividual = inputQuantity;
        } else {
          quantityLargeUnit = inputQuantity;
        }
        
        // حساب التكلفة الفعلية بناءً على نوع الوحدة المباعة
        final actualCostPrice = _calculateActualCostPrice(_selectedProduct!, selectedUnitForItem, inputQuantity, unitsInLargeUnit: baseUnitsPerSelectedUnit);
        
        final newItem = InvoiceItem(
          invoiceId: 0,
          productId: _selectedProduct!.id,
          productName: _selectedProduct!.name,
          unit: _selectedProduct!.unit,
          unitPrice: _selectedProduct!.unitPrice,
          costPrice: finalItemCostPrice,
          actualCostPrice: actualCostPrice,
          quantityIndividual: quantityIndividual,
          quantityLargeUnit: quantityLargeUnit,
          appliedPrice: finalAppliedPrice,
          itemTotal: finalItemTotal,
          saleType: selectedUnitForItem,
          unitsInLargeUnit: baseUnitsPerSelectedUnit != 1.0 ? baseUnitsPerSelectedUnit : null,
        );
        setState(() {
          final existingIndex = invoiceItems.indexWhere((item) =>
              item.productName == newItem.productName &&
              item.saleType == newItem.saleType &&
              item.unit == newItem.unit);
          if (existingIndex != -1) {
            final existingItem = invoiceItems[existingIndex];
            invoiceItems[existingIndex] = existingItem.copyWith(
              quantityIndividual: (existingItem.quantityIndividual ?? 0) +
                  (newItem.quantityIndividual ?? 0),
              quantityLargeUnit: (existingItem.quantityLargeUnit ?? 0) +
                  (newItem.quantityLargeUnit ?? 0),
              itemTotal: (existingItem.itemTotal) + (newItem.itemTotal),
              costPrice:
                  (existingItem.costPrice ?? 0) + (newItem.costPrice ?? 0),
              unitsInLargeUnit: newItem.unitsInLargeUnit,
            );
          } else {
            invoiceItems.add(newItem);
          }
          _productSearchController.clear();
          _quantityController.clear();
          _selectedProduct = null;
          _selectedPriceLevel = null;
          _searchResults = [];
          selectedUnitForItem = 'قطعة';
          currentUnitOptions = ['قطعة'];
          _currentUnitHierarchy = [];
          _guardDiscount();
          _updatePaidAmountIfCash();
          _calculateProfit(); // Update profit on item addition
          
          // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
          if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
            final newTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal) - discount;
            paidAmountController.text = formatNumber(newTotal);
          }
          
          _autoSave();
          if (invoiceToManage != null &&
              invoiceToManage!.status == 'معلقة' &&
              (invoiceToManage?.isLocked ?? false)) {
            autoSaveSuspendedInvoice();
          }
          // --- معالجة الصفوف الفارغة ---
          // احذف جميع الصفوف الفارغة (غير المكتملة)
          invoiceItems.removeWhere((item) => !_isInvoiceItemComplete(item));
          // ثم أضف صف فارغ جديد إذا كان آخر صف مكتمل أو القائمة فارغة
          if (invoiceItems.isEmpty ||
              _isInvoiceItemComplete(invoiceItems.last)) {
            invoiceItems.add(InvoiceItem(
              invoiceId: 0,
              productName: '',
              unit: '',
              unitPrice: 0.0,
              appliedPrice: 0.0,
              itemTotal: 0.0,
              uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
            ));
          }
        });
      }
    } catch (e) {
      print('Error adding invoice item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إضافة الصنف: $e')),
        );
      }
    }
  }

  void _removeInvoiceItem(int index) {
    try {
      if (index < 0 || index >= invoiceItems.length) return;
      _removeInvoiceItemByUid(invoiceItems[index].uniqueId);
    } catch (e) {
      print('Error removing invoice item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حذف الصنف: $e')),
        );
      }
    }
  }

  void _removeInvoiceItemByUid(String uid) {
    try {
      // 🔒 شرط 1: منع حذف جميع الأصناف عند تعديل فاتورة محفوظة
      // يجب أن يبقى صنف واحد على الأقل
      final completeItems = invoiceItems.where((item) => 
        item.productName.isNotEmpty && item.itemTotal > 0
      ).toList();
      
      if (invoiceToManage != null && completeItems.length <= 1) {
        // تحقق إذا كان الصنف المراد حذفه هو الصنف الوحيد المكتمل
        final itemToRemove = invoiceItems.firstWhere(
          (it) => it.uniqueId == uid,
          orElse: () => InvoiceItem(
            invoiceId: 0, productName: '', unit: '', unitPrice: 0,
            appliedPrice: 0, itemTotal: 0, uniqueId: '',
          ),
        );
        if (itemToRemove.productName.isNotEmpty && itemToRemove.itemTotal > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ لا يمكن حذف جميع الأصناف! يجب أن يبقى صنف واحد على الأقل'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
      }
      
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      setState(() {
        final index = invoiceItems.indexWhere((it) => it.uniqueId == uid);
        if (index == -1) return;
        if (index < focusNodesList.length) {
          focusNodesList[index].dispose();
          focusNodesList.removeAt(index);
        }
        invoiceItems.removeAt(index);
        _guardDiscount();
        _updatePaidAmountIfCash();
        
        // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
        if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
          final newTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal) - discount;
          paidAmountController.text = formatNumber(newTotal);
        }
        
        _recalculateTotals();
        _calculateProfit(); // Update profit on item removal
        _autoSave();
        if (invoiceToManage != null &&
            invoiceToManage!.status == 'معلقة' &&
            (invoiceToManage?.isLocked ?? false)) {
          autoSaveSuspendedInvoice();
        }
      });
      _scheduleLiveDebtSync();
    } catch (e) {
      print('Error removing invoice item by uid: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حذف الصنف: $e')),
        );
      }
    }
  }


  Future<String> _saveInvoicePdf(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
    try {
      final safeCustomerName =
          customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
      final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
      final fileName = '${safeCustomerName}_$formattedDate.pdf';
      final directory = Directory(
          '${Platform.environment['USERPROFILE']}/Documents/invoices');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final filePath = '${directory.path}/fileName';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      return filePath;
    } catch (e) {
      print('Error saving PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حفظ ملف PDF: $e')),
        );
      }
      rethrow;
    }
  }

  // حفظ في مجلد مؤقت مناسب للمشاركة (Android/Windows/macOS)
  Future<String> _saveInvoicePdfToTemp(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
    final safeCustomerName =
        customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
    final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
    final fileName = '${safeCustomerName}_$formattedDate.pdf';
    final dir = await pp.getTemporaryDirectory();
    final folder = Directory(p.join(dir.path, 'invoices_share_cache'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final filePath = p.join(folder.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save(), flush: true);
    return filePath;
  }

  Future<void> _printPickingList() async {
    try {
      // تحميل الخطوط والشعار كما في خدمة PDF
      final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      final alnaserFontData = await rootBundle.load('assets/fonts/PTBLDHAD.TTF');
      final font = pw.Font.ttf(fontData);
      final alnaserFont = pw.Font.ttf(alnaserFontData);
      
      // تحميل الإعدادات العامة
      final appSettings = await SettingsManager.getAppSettings();
      
      // تحميل اللوجو باستخدام خدمة اللوجو (مخصص أو افتراضي)
      final logoImage = await LogoService.getLogoImage(appSettings: appSettings);

      final doc = await InvoicePdfService.generatePickingListPdf(
        invoiceItems: invoiceItems,
        allProducts: await db.getAllProducts(),
        customerName: customerNameController.text,
        invoiceId: invoiceToManage?.id ?? 0,
        selectedDate: selectedDate,
        font: font,
        alnaserFont: alnaserFont,
        logoImage: logoImage,
        appSettings: appSettings,
      );

      // 🌐 الويب: PDF من الذاكرة مباشرة — فتح نافذة طباعة المتصفح مباشرة
      if (kIsWeb) {
        final bytes = await doc.save();
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => bytes,
          name: 'قائمة_تجهيز_${customerNameController.text.isNotEmpty ? customerNameController.text : "عامة"}.pdf',
        );
        return;
      }

      // احفظ ثم افتح للطباعة على ويندوز
      final filePath = await _saveInvoicePdfToTemp(doc, customerNameController.text, selectedDate);
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '/min', '', filePath, '/p']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال قائمة التجهيز للطابعة')),
          );
        }
        return;
      }
      // على أندرويد/منصات أخرى: مشاركة/فتح الملف ليطبعه المستخدم
      final fileName = p.basename(filePath);
      await Share.shareXFiles([
        XFile(
          filePath,
          mimeType: 'application/pdf',
          name: fileName,
        )
      ], text: 'قائمة تجهيز ${customerNameController.text}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل طباعة التجهيز: $e')),
        );
      }
    }
  }

  // حوار خطوات التسوية: اختيار (إضافة/حذف) ثم (بند/مبلغ)
  Future<void> _openSettlementChoice() async {
    if (invoiceToManage == null) return;
    // Dialog 1: إضافة / حذف
    String? op = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسوية الفاتورة'),
        content: const Text('اختر نوع العملية'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'credit'), child: const Text('حذف (راجع)')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'debit'), child: const Text('إضافة')),
        ],
      ),
    );
    if (op == null) return;
    _settlementIsDebit = (op == 'debit');

    // Dialog 2: بند / مبلغ + ملاحظة
    String? mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طريقة التسوية'),
        content: const Text('اختر تسوية ببند أم مبلغ مباشر؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'amount'), child: const Text('مبلغ + ملاحظة')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'item'), child: const Text('بند (أصناف)')),
        ],
      ),
    );
    if (mode == null) return;
    if (mode == 'amount') {
      await _openSettlementAmountDialog();
      return;
    }
    // mode == item ⇒ افتح لوحة الأصناف أسفل الجدول
    setState(() {
      settlementPanelVisible = true;
      _settlementItems.clear();
      _settleSelectedProduct = null;
      _settleSelectedSaleType = 'قطعة';
      _settleNameCtrl.clear();
      _settleIdCtrl.clear();
      _settleQtyCtrl.clear();
      _settlePriceCtrl.clear();
      _settleUnitCtrl.clear();
      _settlementPaymentType = (invoiceToManage?.paymentType == 'دين') ? 'دين' : 'نقد';
    });
  }

  // دالة تفعيل وضع التعديل
  Future<void> _enableEditMode() async {
    // 🔒 تثبيت الإدخالات: لا تعديل لفاتورة داخل فترة مثبّتة
    if (!await PeriodLock.guard(context, invoiceToManage?.invoiceDate)) return;
    if (!mounted) return;
    setState(() {
      isViewOnly = false;
    });
    
    // إظهار رسالة تأكيد
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تفعيل وضع التعديل - يمكنك الآن إضافة أو حذف أصناف'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // دالة إلغاء التعديل - تستعيد جميع البيانات الأصلية
  Future<void> _cancelEdit() async {
    if (invoiceToManage == null) return;
    
    // جلب الفاتورة الأصلية من قاعدة البيانات
    final originalInvoice = await db.getInvoiceById(invoiceToManage!.id!);
    if (originalInvoice == null) return;
    
    setState(() {
      // استعادة بيانات العميل
      customerNameController.text = originalInvoice.customerName;
      customerPhoneController.text = originalInvoice.customerPhone ?? '';
      customerAddressController.text = originalInvoice.customerAddress ?? '';
      
      // استعادة بيانات الفني
      installerNameController.text = originalInvoice.installerName ?? '';
      
      // استعادة التاريخ
      selectedDate = originalInvoice.invoiceDate;
      
      // استعادة نوع الدفع
      paymentType = originalInvoice.paymentType;
      
      // استعادة الخصم
      discount = originalInvoice.discount;
      discountController.text = formatNumber(discount);
      
      // استعادة المبلغ المدفوع
      paidAmountController.text = formatNumber(originalInvoice.amountPaidOnInvoice);
      
      // استعادة أجور التحميل
      final itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final loadingFee = originalInvoice.totalAmount - itemsTotal;
      loadingFeeController.text = loadingFee > 0 ? formatNumber(loadingFee) : '';
      

      
      // تحديث الفاتورة المُدارة
      invoiceToManage = originalInvoice;
      
      // العودة لوضع العرض فقط
      isViewOnly = true;
      hasUnsavedChanges = false;
    });
    
    // إعادة تحميل الأصناف من قاعدة البيانات
    await _loadInvoiceItems();
    
    // تحديث الإجمالي
    _recalculateTotals();
    
    // إظهار رسالة تأكيد
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء التعديل - تم استعادة جميع البيانات الأصلية'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // فحص إذا كانت التسويات الراجعة تتجاوز المبلغ المتبقي الفعلي
  Future<bool> _isRefundExceedingRemaining(double newRefundAmount) async {
    if (invoiceToManage == null) return false;
    
    // حساب المبلغ المتبقي الحالي
    final remainingAmount = await _calculateRemainingAmount();
    
    // إضافة التسوية الجديدة
    final totalRefunds = remainingAmount + newRefundAmount.abs();
    
    // فحص إذا تجاوزت المبلغ المتبقي (أصبحت سالبة)
    return totalRefunds < 0;
  }

  // حساب المبلغ المتبقي بعد التسويات
  Future<double> _calculateRemainingAmount() async {
    if (invoiceToManage == null) return 0.0;
    
    // حساب إجمالي الفاتورة - totalAmount يحتوي على الخصم مسبقاً
    final afterDiscount = invoiceToManage!.totalAmount;
    
    // حساب التسويات
    final adjustments = await db.getInvoiceAdjustments(invoiceToManage!.id!);
    final cashSettlements = adjustments
        .where((adj) => adj.settlementPaymentType == 'نقد')
        .fold<double>(0.0, (sum, adj) => sum + adj.amountDelta);
    final debtSettlements = adjustments
        .where((adj) => adj.settlementPaymentType == 'دين')
        .fold<double>(0.0, (sum, adj) => sum + adj.amountDelta);
    
    // حساب المبلغ المدفوع المعروض
    final double displayedPaid;
    if (invoiceToManage!.paymentType == 'نقد' && adjustments.isNotEmpty) {
      // للفواتير النقدية مع تسويات: المبلغ المدفوع = المبلغ الأصلي + التسويات النقدية فقط
      displayedPaid = invoiceToManage!.amountPaidOnInvoice + cashSettlements;
    } else {
      // للفواتير بالدين أو الفواتير النقدية بدون تسويات
      displayedPaid = invoiceToManage!.amountPaidOnInvoice + cashSettlements;
    }
    
    // حساب المبلغ المتبقي
    return afterDiscount - displayedPaid;
  }

  Future<void> _openSettlementAmountDialog() async {
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    // الإرجاع/الحذف لا يملك خيار (دين/نقد) ويجب أن يؤثر على الدين تلقائياً
    String paymentKind = _settlementIsDebit
        ? ((invoiceToManage?.paymentType == 'دين') ? 'دين' : 'نقد')
        : 'دين';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_settlementIsDebit ? 'إضافة مبلغ' : 'حذف (راجع) مبلغ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ'),
            ),
            if (_settlementIsDebit) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: paymentKind,
                onChanged: (v) { if (v != null) paymentKind = v; },
                items: const [
                  DropdownMenuItem(value: 'دين', child: Text('دين')),
                  DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                ],
                decoration: const InputDecoration(labelText: 'طريقة دفع التسوية'),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || invoiceToManage == null) return;
    final v = double.tryParse(amountCtrl.text.trim());
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صحيحاً')));
      return;
    }
    final delta = _settlementIsDebit ? v.abs() : -v.abs();
    
    // فحص إذا كانت التسوية راجعة وتتجاوز المبلغ المتبقي الفعلي
    if (!_settlementIsDebit) {
      final isExceeding = await _isRefundExceedingRemaining(v.abs());
      if (isExceeding) {
        final remainingAmount = await _calculateRemainingAmount();
        final maxAllowedRefund = remainingAmount.abs();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('التسوية الراجعة تتجاوز المبلغ المتبقي. الحد الأقصى المسموح: ${formatNumber(maxAllowedRefund, forceDecimal: true)} دينار'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    
    await db.insertInvoiceAdjustment(InvoiceAdjustment(
      invoiceId: invoiceToManage!.id!,
      type: _settlementIsDebit ? 'debit' : 'credit',
      amountDelta: delta,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      settlementPaymentType: paymentKind,
    ));
    await _loadSettlementInfo();
    
    // فحص إذا كان المبلغ المتبقي أصبح سالباً (يحتاج كاش)
    if (mounted) {
      final remainingAmount = await _calculateRemainingAmount();
      if (remainingAmount < 0) {
        final cashToGive = (-remainingAmount).abs();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تنبيه'),
            content: Text('يجب أن تعطيه ${formatNumber(cashToGive, forceDecimal: true)} دينار عراقي'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('موافق'),
              ),
            ],
          ),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تسوية المبلغ')));
    }
  }
  Widget _buildSettlementPanel() {
    final Color gridBorderColor = Colors.grey.shade300;
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_settlementIsDebit ? 'تسوية: إضافة بنود' : 'تسوية: حذف (راجع) بنود', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => settlementPanelVisible = false),
                  icon: const Icon(Icons.close),
                  label: const Text('إخفاء'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _settlementPaymentType,
                    onChanged: (v) {
                      if (v != null) setState(() => _settlementPaymentType = v);
                    },
                    items: const [
                      DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                      DropdownMenuItem(value: 'دين', child: Text('دين')),
                    ],
                    decoration: const InputDecoration(labelText: 'طريقة دفع التسوية'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // جدول تسوية بنفس تصميم جدول الفاتورة
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: gridBorderColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  // رأس الجدول
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(bottom: BorderSide(color: gridBorderColor)),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 1, child: Text('ت', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('المبلغ', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('ID', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text('التفاصيل', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('العدد', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('نوع البيع', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('السعر', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('عدد الوحدات', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('حذف', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  // صف إدخال جديد
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: gridBorderColor)),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 1, child: Text('${_settlementItems.length + 1}', textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('', textAlign: TextAlign.center)), // المبلغ سيحسب تلقائياً
                        Expanded(
                          flex: 1,
                          child: Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) async {
                              if (textEditingValue.text.isEmpty) {
                                return const Iterable<String>.empty();
                              }
                              final v = textEditingValue.text.trim();
                              final id = int.tryParse(v);
                              if (id == null) return const Iterable<String>.empty();
                              final db = DatabaseService();
                              final suggestions = await db.searchProductsByIdPrefix(v, limit: 8);
                              return suggestions.map((p) => p.name);
                            },
                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                              // ربط controller مع _settleIdController
                              _settleIdController = controller;
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  hintText: 'ID',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                  isDense: true,
                                ),
                                onSubmitted: (val) async {
                                  final id = int.tryParse(val.trim());
                                  if (id == null) return;
                                  final p = await db.getProductById(id);
                                  if (p != null) {
                                    _applySettlementProductSelection(p);
                                  }
                                },
                              );
                            },
                            onSelected: (String selection) {
                              try {
                                // 🧠 البحث عن المنتج المحدد وتطبيق التعبئة التلقائية (باستخدام البحث الذكي)
                                final currentProductNames = invoiceItems
                                    .where((item) => item.productName.isNotEmpty)
                                    .map((item) => item.productName)
                                    .toList();
                                SmartSearchService.instance.smartSearch(
                                  selection,
                                  currentInvoiceProductNames: currentProductNames,
                                ).then((products) {
                                  if (products.isNotEmpty) {
                                    _applySettlementProductSelection(products.first);
                                  }
                                });
                              } catch (e) {}
                            },
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) async {
                              if (textEditingValue.text.isEmpty) {
                                return const Iterable<String>.empty();
                              }
                              // 🧠 استخدام البحث الذكي مع قائمة المنتجات الحالية
                              final currentProductNames = invoiceItems
                                  .where((item) => item.productName.isNotEmpty)
                                  .map((item) => item.productName)
                                  .toList();
                              final results = await SmartSearchService.instance.smartSearch(
                                textEditingValue.text,
                                currentInvoiceProductNames: currentProductNames,
                              );
                              return results.map((p) => p.name);
                            },
                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                              // ربط controller مع _settleNameController
                              _settleNameController = controller;
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  hintText: 'التفاصيل',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                  isDense: true,
                                ),
                                // عند الكتابة لا نقوم باختيار أول نتيجة تلقائياً؛ نعرض الاقتراحات فقط،
                                // ويتم تطبيق الاختيار عند تحديد عنصر من القائمة أو تأكيد الإدخال.
                              );
                            },
                            onSelected: (String selection) {
                              try {
                                // 🧠 البحث عن المنتج المحدد وتطبيق التعبئة التلقائية (باستخدام البحث الذكي)
                                final currentProductNames = invoiceItems
                                    .where((item) => item.productName.isNotEmpty)
                                    .map((item) => item.productName)
                                    .toList();
                                SmartSearchService.instance.smartSearch(
                                  selection,
                                  currentInvoiceProductNames: currentProductNames,
                                ).then((products) {
                                  if (products.isNotEmpty) {
                                    _applySettlementProductSelection(products.first);
                                  }
                                });
                              } catch (e) {}
                            },
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _settleQtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              hintText: 'العدد',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              isDense: true,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _settleSelectedSaleType,
                              items: _getSettlementUnitOptions(),
                              onChanged: (value) {
                                setState(() {
                                  _settleSelectedSaleType = value!;
                                });
                              },
                              isExpanded: true,
                              alignment: AlignmentDirectional.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _settlePriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              hintText: 'السعر',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              isDense: true,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.grey[100],
                            ),
                            child: Text(
                              _settleSelectedProduct?.piecesPerUnit?.toStringAsFixed(0) ?? '1',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: ElevatedButton(
                            onPressed: _addSettlementRow,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              minimumSize: Size.zero,
                            ),
                            child: const Text('إضافة', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // الأصناف المضافة
                  for (int i = 0; i < _settlementItems.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: gridBorderColor)),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 1, child: Text('${i + 1}', textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(_settlementItems[i].itemTotal.toStringAsFixed(2), textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(_settlementItems[i].productId?.toString() ?? '', textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text(_settlementItems[i].productName, textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text((_settlementItems[i].quantityIndividual ?? _settlementItems[i].quantityLargeUnit ?? 0).toString(), textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(_settlementItems[i].unit, textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(_settlementItems[i].appliedPrice.toStringAsFixed(2), textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text('', textAlign: TextAlign.center)), // عدد الوحدات
                          Expanded(
                            flex: 1,
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                              onPressed: () => setState(() => _settlementItems.removeAt(i)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isSaving ? null : _saveSettlementItems,
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ بنود التسوية'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _addSettlementRow() {
    final name = _settleNameCtrl.text.trim();
    final qty = double.tryParse(_settleQtyCtrl.text.trim());
    final price = double.tryParse(_settlePriceCtrl.text.trim());
    // احسب عدد الوحدات الأساسية داخل وحدة البيع المختارة باستخدام الهرمية
    double unitsCount = 1.0;
    if (_settleSelectedProduct != null) {
      final prod = _settleSelectedProduct!;
      if (_settleSelectedSaleType == 'قطعة' || _settleSelectedSaleType == 'متر') {
        unitsCount = 1.0;
      } else if (prod.unit == 'meter' && _settleSelectedSaleType == 'لفة') {
        unitsCount = prod.lengthPerUnit?.toDouble() ?? 1.0;
      } else {
        // للمنتجات بالقطعة: احسب الضرب التراكمي حتى تصل للوحدة المطلوبة
        try {
          final List<Map<String, dynamic>> hierarchy = prod.getUnitHierarchyList();
          double cumulative = 1.0;
          for (final level in hierarchy) {
            final String levelName = (level['unit_name'] ?? level['name'] ?? '').toString();
            final double q = (level['quantity'] is num)
                ? (level['quantity'] as num).toDouble()
                : double.tryParse(level['quantity']?.toString() ?? '') ?? 1.0;
            cumulative = cumulative * (q > 0 ? q : 1.0);
            if (levelName == _settleSelectedSaleType) {
              unitsCount = cumulative;
              break;
            }
          }
        } catch (_) {
          unitsCount = 1.0;
        }
      }
    }
    
    if (name.isEmpty || qty == null || qty <= 0 || price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل التفاصيل والعدد والسعر بشكل صحيح')));
      return;
    }
    
    final item = InvoiceItem(
      invoiceId: 0,
      productId: _settleSelectedProduct?.id,
      productName: name,
      unit: _settleSelectedProduct?.unit ?? 'piece',
      unitPrice: _settleSelectedProduct?.unitPrice ?? price,
      appliedPrice: price,
      itemTotal: price * qty,
      quantityIndividual: (_settleSelectedSaleType == 'قطعة' || _settleSelectedSaleType == 'متر') ? qty : null,
      quantityLargeUnit: (_settleSelectedSaleType != 'قطعة' && _settleSelectedSaleType != 'متر') ? qty : null,
      saleType: _settleSelectedSaleType,
      unitsInLargeUnit: unitsCount,
      uniqueId: 'settle_${DateTime.now().microsecondsSinceEpoch}',
    );
    
    setState(() {
      _settlementItems.add(item);
      _settleQtyCtrl.clear();
      _settlePriceCtrl.clear();
    });
  }

  void _applySettlementProductSelection(Product prod) {
    setState(() {
      _settleSelectedProduct = prod;
      // ملء حقل ID بالمعرف
      _settleIdCtrl.text = prod.id?.toString() ?? '';
      // ملء حقل التفاصيل بالاسم
      _settleNameCtrl.text = prod.name;
      // ملء حقل السعر
      _settlePriceCtrl.text = (prod.price1 ?? prod.unitPrice).toString();
      
      // تحديد نوع البيع المناسب بناءً على الخيارات المتاحة
      List<String> availableOptions = _getAvailableUnitOptions(prod);
      if (availableOptions.isNotEmpty) {
        _settleSelectedSaleType = availableOptions.first;
      } else {
        _settleSelectedSaleType = 'قطعة';
      }
    });
    
    // تحديث controller في Autocomplete مباشرة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // تحديث حقل ID
        _settleIdController?.text = prod.id?.toString() ?? '';
        // تحديث حقل التفاصيل
        _settleNameController?.text = prod.name;
      }
    });
  }

  List<String> _getAvailableUnitOptions(Product prod) {
    List<String> options = ['قطعة'];
    if (prod.unit == 'piece' && 
        prod.unitHierarchy != null && 
        prod.unitHierarchy!.isNotEmpty) {
      try {
        List<dynamic> hierarchy = json.decode(prod.unitHierarchy!.replaceAll("'", '"'));
        options.addAll(hierarchy.map((e) => (e['unit_name'] ?? e['name']).toString()));
      } catch (e) {}
    } else if (prod.unit == 'meter' && prod.lengthPerUnit != null) {
      options = ['متر'];
      options.add('لفة');
    } else if (prod.unit != 'piece' && prod.unit != 'meter') {
      options = [prod.unit];
    }
    
    // إزالة التكرار والقيم الفارغة
    return options.where((e) => e.isNotEmpty).toSet().toList();
  }

  List<DropdownMenuItem<String>> _getSettlementUnitOptions() {
    if (_settleSelectedProduct == null) {
      return [const DropdownMenuItem(value: 'قطعة', child: Text('قطعة', textAlign: TextAlign.center))];
    }
    
    List<String> options = _getAvailableUnitOptions(_settleSelectedProduct!);
    
    // التأكد من أن القيمة المحددة موجودة في القائمة
    if (!options.contains(_settleSelectedSaleType)) {
      _settleSelectedSaleType = options.first;
    }
    
    return options.map((unit) => DropdownMenuItem(
      value: unit,
      child: Text(unit, textAlign: TextAlign.center),
    )).toList();
  }

  Future<void> _saveSettlementItems() async {
    if (invoiceToManage == null || _settlementItems.isEmpty) return;
    
    // فحص إذا كانت التسويات الراجعة تتجاوز المبلغ المتبقي الفعلي
    if (!_settlementIsDebit) {
      final totalRefundAmount = _settlementItems.fold<double>(0.0, (sum, item) => sum + item.itemTotal);
      final isExceeding = await _isRefundExceedingRemaining(totalRefundAmount);
      if (isExceeding) {
        final remainingAmount = await _calculateRemainingAmount();
        final maxAllowedRefund = remainingAmount.abs();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('التسويات الراجعة تتجاوز المبلغ المتبقي. الحد الأقصى المسموح: ${formatNumber(maxAllowedRefund, forceDecimal: true)} دينار'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    
    for (final it in _settlementItems) {
      final delta = (_settlementIsDebit ? 1 : -1) * (it.itemTotal);
      final paymentType = _settlementIsDebit ? _settlementPaymentType : 'دين';
      
      await db.insertInvoiceAdjustment(InvoiceAdjustment(
        invoiceId: invoiceToManage!.id!,
        type: _settlementIsDebit ? 'debit' : 'credit',
        amountDelta: delta,
        productId: it.productId,
        productName: it.productName,
        quantity: (it.quantityIndividual ?? it.quantityLargeUnit ?? 0).toDouble(),
        price: it.appliedPrice,
        unit: it.unit,
        saleType: it.saleType,
        unitsInLargeUnit: it.unitsInLargeUnit,
        settlementPaymentType: paymentType,
        note: 'تسوية بند',
      ));
    }
    if (mounted) {
      setState(() {
        settlementPanelVisible = false;
        _settlementItems.clear();
        _settleSelectedProduct = null;
        _settleSelectedSaleType = 'قطعة';
        _settleNameCtrl.clear();
        _settleIdCtrl.clear();
        _settleQtyCtrl.clear();
        _settlePriceCtrl.clear();
        _settleUnitCtrl.clear();
      });
      
      // فحص إذا كان المبلغ المتبقي أصبح سالباً (يحتاج كاش)
      final remainingAmount = await _calculateRemainingAmount();
      if (remainingAmount < 0) {
        final cashToGive = (-remainingAmount).abs();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تنبيه'),
            content: Text('يجب أن تعطيه ${formatNumber(cashToGive, forceDecimal: true)} دينار عراقي'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('موافق'),
              ),
            ],
          ),
        );
      }
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ بنود التسوية')));
    }
  }

  // حفظ التسوية كأصناف جديدة مرتبطة بالفاتورة الأساسية عبر invoice_adjustments
  Future<void> _saveSettlement() async {
    try {
      if (widget.settlementForInvoice == null) return;
      final baseInvoice = widget.settlementForInvoice!;
      // صفّ البيانات الفارغة وأحسب الإجمالي
      final settlementItems = invoiceItems.where((it) => _isInvoiceItemComplete(it)).toList();
      if (settlementItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف بنوداً للتسوية أولاً')));
        return;
      }
      for (final item in settlementItems) {
        // المبلغ للبند
        final double qty = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0).toDouble();
        final double price = item.appliedPrice;
        final double delta = qty * price;
        // البحث عن المنتج لتعويض productId
        Product? prod;
        try {
          final all = await db.getAllProducts();
          prod = all.firstWhere((p) => p.name == item.productName);
        } catch (_) {}
        await db.insertInvoiceAdjustment(
          InvoiceAdjustment(
            invoiceId: baseInvoice.id!,
            type: 'debit',
            amountDelta: delta,
            productId: prod?.id,
            productName: item.productName,
            quantity: qty,
            price: price,
            note: 'تسوية بند',
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التسوية وربطها بالفاتورة')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ التسوية: $e')));
    }
  }

  void _resetInvoice() {
    try {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('فاتورة جديدة'),
          content: const Text(
              'هل تريد بدء فاتورة جديدة؟ سيتم مسح جميع البيانات الحالية.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _performReset();
              },
              child: const Text('نعم'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('Error resetting invoice: $e');
    }
  }

  Future<void> _performReset() async {
    try {
      setState(() {
        customerNameController.clear();
        customerPhoneController.clear();
        customerAddressController.clear();
        installerNameController.clear();
        _productSearchController.clear();
        _quantityController.clear();
        paidAmountController.clear();
        discountController.clear();
        discount = 0.0;
        _selectedPriceLevel = null;
        _selectedProduct = null;
        _useLargeUnit = false;
        paymentType = 'نقد';
        selectedDate = DateTime.now();
        invoiceItems.clear(); // حذف جميع الأصناف فورًا
        for (final node in focusNodesList) {
          node.dispose();
        }
        focusNodesList.clear();
        _searchResults.clear();
        _totalAmountController.text = '0';
        savedOrSuspended = false;
      });
      
      await storage.delete(key: 'temp_invoice_data');

      // بعد ثانية واحدة أضف عنصر فارغ جديد
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            invoiceItems.add(InvoiceItem(
              invoiceId: 0,
              productName: '',
              unit: '',
              unitPrice: 0.0,
              appliedPrice: 0.0,
              itemTotal: 0.0,
              uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
            ));
            focusNodesList.add(LineItemFocusNodes());
          });
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم بدء فاتورة جديدة')),
      );
    } catch (e) {
      print('Error performing reset: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء بدء فاتورة جديدة: $e')),
        );
      }
    }
  }

  Future<void> _saveReturnAmount(double value) async {
    try {
      if (invoiceToManage == null || invoiceToManage!.isLocked) return;
      // تحديث الفاتورة في قاعدة البيانات
      final updatedInvoice =
          invoiceToManage!.copyWith(isLocked: true);
      await db.updateInvoice(updatedInvoice);

      // إزالة منطق خصم الراجع من رصيد المؤسس
      if (updatedInvoice.installerName != null &&
          updatedInvoice.installerName!.isNotEmpty) {
        final installer =
            await db.getInstallerByName(updatedInvoice.installerName!);
        if (installer != null) {
          final newTotal =
              (installer.totalBilledAmount - value).clamp(0.0, double.infinity);
          final updatedInstaller =
              installer.copyWith(totalBilledAmount: newTotal);
          await db.updateInstaller(updatedInstaller);
        }
      }

      // إزالة منطق دين العميل المرتبط بالراجع

      // جلب أحدث نسخة من الفاتورة بعد الحفظ
      final updatedInvoiceFromDb =
          await db.getInvoiceById(invoiceToManage!.id!);
      setState(() {
        invoiceToManage = updatedInvoiceFromDb;
        isViewOnly = true; // تفعيل وضع العرض فقط
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم قفل الفاتورة!')), 
        );
        Navigator.of(context)
            .popUntil((route) => route.isFirst); // العودة للصفحة الرئيسية
      }
    } catch (e) {
      print('Error saving return amount: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حفظ الراجع: $e')),
        );
      }
    }
  }

  // دالة الحفظ التلقائي للفواتير المعلقة
  Future<void> autoSaveSuspendedInvoice() async {
    try {
      if (invoiceToManage == null ||
          invoiceToManage!.status != 'معلقة' ||
          (invoiceToManage?.isLocked ?? false)) return;
      // 🛡️ فاتورة من نسخة احتياطية مستعادة والجهاز لم يلحق بالبقية: لا حفظ
      // تلقائي (كان سيغيّر أصنافها ثم يُرفض تحديث الفاتورة نفسها — حفظ ناقص)
      if (await db.isRestoredRecordLocked('invoices', invoiceToManage!.id!)) return;
      Customer? customer;
      if (customerNameController.text.trim().isNotEmpty) {
        final customers = await db.getAllCustomers();
        try {
          customer = customers.firstWhere(
            (c) =>
                c.name.trim() == customerNameController.text.trim() &&
                (c.phone == null ||
                    c.phone!.isEmpty ||
                    customerPhoneController.text.trim().isEmpty ||
                    c.phone == customerPhoneController.text.trim()),
          );
        } catch (e) {
          customer = null;
        }
        // لا تنشئ عميل جديد هنا، فقط استخدم الموجود إن وجد
      }
      double currentTotalAmount =
          invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      // تضمين أجور التحميل في الإجمالي الفعلي عند الحفظ/التعديل
      final double loadingFee =
          double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
              0.0;
      double paid =
          double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
              0.0;
      double totalAmount = (currentTotalAmount + loadingFee) - discount;
      Invoice invoice = invoiceToManage!.copyWith(
        customerName: customerNameController.text,
        customerPhone: customerPhoneController.text,
        customerAddress: customerAddressController.text,
        installerName: installerNameController.text.isEmpty
            ? null
            : installerNameController.text,
        invoiceDate: selectedDate,
        paymentType: paymentType,
        totalAmount: totalAmount,
        discount: discount,
        amountPaidOnInvoice: paid,
        loadingFee: loadingFee,
        lastModifiedAt: DateTime.now(),
        customerId: customer?.id,
        // status: 'معلقة',
        isLocked: false,
      );
      int invoiceId = invoiceToManage!.id!;
      // حذف جميع أصناف الفاتورة القديمة وإضافة الجديدة
      final oldItems = await db.getInvoiceItems(invoiceId);
      for (var oldItem in oldItems) {
        await db.deleteInvoiceItem(oldItem.id!);
      }
      for (var item in invoiceItems) {
        item.invoiceId = invoiceId;
        await db.insertInvoiceItem(item);
      }
      await context.read<AppProvider>().updateInvoice(invoice);
      setState(() {
        invoiceToManage = invoice;
      });
    } catch (e) {
      print('Auto-save suspended invoice error: $e');
    }
  }

  // 🔒 التحقق من المخزون عند الكتابة اليدوية في شريط الإدخال
  void _validateEntryStockByManualName(String name) {
    if (_allowNegativeStock) {
      if (_isEntryLocked) setState(() => _isEntryLocked = false);
      return;
    }
    
    final sanitizedInput = name.trim().replaceAll(' ', '');
    if (sanitizedInput.isEmpty) {
       if (_isEntryLocked) setState(() => _isEntryLocked = false);
       return;
    }

    Product? matchingProduct;
    try {
      // مقارنة الاسم بدون فواصل كما طلب المستخدم
      matchingProduct = (_allProductsForUnits ?? []).firstWhere(
        (p) => p.name.trim().replaceAll(' ', '') == sanitizedInput,
      );
    } catch (_) {}

    final shouldLock = matchingProduct != null && (matchingProduct.stockQuantity ?? 0) <= 0;
    
    if (shouldLock != _isEntryLocked) {
      setState(() {
        _isEntryLocked = shouldLock;
      });
      
      if (shouldLock) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ هذا الصنف نافذ من المخزون! تم قفل الإدخال.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // 2. أضف دالة توليد الوحدات:
  void _onProductSelected(Product product) {
    try {
      final bool isOutOfStock = (product.stockQuantity ?? 0) <= 0;
      final bool entryLocked = isOutOfStock && !_allowNegativeStock;

      setState(() {
        _selectedProduct = product;
        _isEntryLocked = entryLocked;
        _quantityController.clear();
        _productSearchController.text = product.name;
        
        if (entryLocked) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ هذا الصنف نافذ من المخزون! تم قفل الإدخال.'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 2),
            ),
          );
        }

        _currentUnitHierarchy = [];
        currentUnitOptions = [];
        // 🔧 استخدام method موجود في Product model لجلب جميع الوحدات
        final allUnits = product.getAllUnitLevels();
        if (allUnits.isNotEmpty) {
          currentUnitOptions = allUnits;
          selectedUnitForItem = allUnits.first;
          _currentUnitHierarchy = product.getUnitHierarchyList();
        } else {
          // Fallback: إذا لم يكن هناك هرمي، استخدم الوحدة الأساسية
          final baseUnit = product.unit == 'piece' ? 'قطعة' : (product.unit == 'meter' ? 'متر' : product.unit);
          currentUnitOptions = [baseUnit];
          selectedUnitForItem = baseUnit;
          _currentUnitHierarchy = [];
        }
        print('DEBUG: product.unitHierarchy = \u001b[32m${product.unitHierarchy}\u001b[0m');
        print('DEBUG: currentUnitOptions = \u001b[36m$currentUnitOptions\u001b[0m');
        // 🔍 تشخيص تحويل الوحدات — لماذا قد لا يتغير السعر للموزونات
        print('🔍 [تشخيص-اختيار-منتج] "${product.name}" (id=${product.id})');
        print('    unit="${product.unit}" | isWeighable=${product.isWeighable} | baseWeight=${product.baseWeight}');
        print('    unitHierarchy=${product.unitHierarchy}');
        print('    الوحدات المتاحة: $currentUnitOptions | المحددة: $selectedUnitForItem');
        print('    price1=${product.price1} | costPrice=${product.costPrice}');
        double? newPriceLevel;
        switch (_selectedListType) {
          case 'مفرد':
            newPriceLevel = product.price1;
            break;
          case 'مفرد 2':
            newPriceLevel = product.price2;
            break;
          case 'منزل':
            newPriceLevel = product.price3;
            break;
          case 'جملة':
            newPriceLevel = product.price4;
            break;
          case 'جملة 2':
            newPriceLevel = product.price5;
            break;
          case 'أخرى':
            newPriceLevel = product.price6;
            break;
          default:
            newPriceLevel = product.price1;
        }
        if (newPriceLevel == null || newPriceLevel == 0) {
          _selectedPriceLevel = null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('المنتج المحدد لا يملك سعر "$_selectedListType".'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          // تحقق أن السعر موجود في قائمة الأسعار
          final validPrices = [
            product.price1,
            product.price2,
            product.price3,
            product.price4,
            product.price5
          ].where((p) => p != null && p > 0).toList();
          if (validPrices.contains(newPriceLevel)) {
            _selectedPriceLevel = newPriceLevel;
          } else {
            _selectedPriceLevel = null;
          }
        }
        suppressSearch = true;
        _productSearchController.text = product.name;
        _searchResults = [];
        quantityAutofocus = true;
      });
      
      // 🧠 تحديث سياق البحث الذكي
      SmartSearchService.instance.addProductToSession(product.id, product.name);
      
      // 💰 ملء السعر تلقائياً حسب نوع القائمة المختارة
      _updatePriceForSelectedProduct(product);
      
      // 🔧 نقل التركيز إلى حقل الكمية العلوي بعد اختيار المنتج
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _quantityFocusNode.requestFocus();
        }
      });
    } catch (e) {
      print('Error selecting product: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء اختيار المنتج: $e')),
        );
      }
    }
  }

  // دالة مساعدة لبناء سلسلة التحويل للوحدة المختارة
  String buildUnitConversionString(
      InvoiceItem item, List<Product> allProducts) {
    // المنتجات التي تباع بالامتار
    if (item.unit == 'meter') {
      if (item.saleType == 'لفة' && item.unitsInLargeUnit != null) {
        return item.unitsInLargeUnit!.toString();
      } else {
        return '';
      }
    }
    // المنتجات التي تباع بالقطعة ولها تسلسل هرمي
    final product = allProducts.firstWhere(
      (p) => p.name == item.productName,
      orElse: () => Product(
        id: null,
        name: item.productName,
        unit: item.unit,
        unitPrice: item.unitPrice,
        costPrice: null,
        piecesPerUnit: null,
        lengthPerUnit: null,
        price1: item.unitPrice,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    if (product.unitHierarchy == null || product.unitHierarchy!.isEmpty) {
      return item.unitsInLargeUnit?.toString() ?? '';
    }
    try {
      final List<dynamic> hierarchy =
          json.decode(product.unitHierarchy!.replaceAll("'", '"'));
      // ابحث عن تسلسل التحويل للوحدة المختارة
      List<String> factors = [];
      for (int i = 0; i < hierarchy.length; i++) {
        final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
        final quantity = hierarchy[i]['quantity'];
        factors.add(quantity.toString());
        if (unitName == item.saleType) {
          break;
        }
      }
      if (factors.isEmpty) {
        return item.unitsInLargeUnit?.toString() ?? '';
      }
      return factors.join(' × ');
    } catch (e) {
      return item.unitsInLargeUnit?.toString() ?? '';
    }
  }

  void _recalculateTotals() {
    double itemsTotal = invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
    // إضافة رسوم التحميل إلى الإجمالي المعروض
    final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
    double total = itemsTotal + loadingFee;
    _totalAmountController.text = formatNumber(total);
    if (paymentType == 'نقد') {
      paidAmountController.text = formatNumber(total - discount);
    }
    setState(() {});
    _scheduleLiveDebtSync();
  }

  Future<void> _syncLiveDebt() async {
    try {
      // متاح فقط للفواتير الموجودة ولها عميل
      if (invoiceToManage == null || invoiceToManage!.id == null) return;
      
      // 🔧 إصلاح: لا تنشئ معاملات invoice_live_update للفواتير المحفوظة
      // المعاملات يجب أن تُنشأ فقط عند الحفظ الفعلي في saveInvoice
      // هذا يمنع إنشاء معاملات زائدة عند فتح الفاتورة للتعديل
      if (invoiceToManage!.status == 'محفوظة') {
        return;
      }
      
      final int invoiceId = invoiceToManage!.id!;
      int? customerId = invoiceToManage!.customerId;
      if (customerId == null) {
        // حاول إيجاد العميل بالاسم/الهاتف إذا لم يكن مرتبطاً
        if (customerNameController.text.trim().isEmpty) return;
        final customer = await db.findCustomerByNormalizedName(
          customerNameController.text.trim(),
          phone: customerPhoneController.text.trim().isEmpty
              ? null
              : customerPhoneController.text.trim(),
        );
        if (customer == null || customer.id == null) return;
        customerId = customer.id;
      }
      final int resolvedCustomerId = customerId!;

      // تحقق مما إذا كانت هناك معاملة دين موجودة بالفعل لهذه الفاتورة
      // لتجنب إنشاء معاملات مكررة
      final existingDebtTransaction = await db.getInvoiceDebtTransaction(invoiceId);
      if (existingDebtTransaction != null) {
        // تم بالفعل إنشاء معاملة دين لهذه الفاتورة، لا تقم بإنشاء أخرى
        return;
      }

      double newContribution = 0.0;
      if (paymentType == 'دين') {
        // 🔧 حساب المتبقي بناءً على القيم الحالية في الشاشة (وليس القيم المحفوظة)
        // هذا يضمن أن الخصم الجديد يُؤخذ بعين الاعتبار
        final double itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
        final double currentTotalAmount = itemsTotal + loadingFee - discount; // الإجمالي بعد الخصم
        final double paidAmount = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0;
        final double remaining = currentTotalAmount - paidAmount;
        newContribution = remaining.clamp(0.0, double.infinity);
      } else {
        newContribution = 0.0;
      }

      await db.setInvoiceDebtContribution(
        invoiceId: invoiceId,
        customerId: resolvedCustomerId,
        newContribution: newContribution,
        note: 'تعديل حي لمساهمة فاتورة #$invoiceId',
      );
    } catch (e) {
      // لا تُظهر خطأ للمستخدم أثناء التعديل الحي؛ فقط سجّل
      print('live debt sync error: $e');
    }
  }

  void _scheduleLiveDebtSync() {
    try {
      liveDebtTimer?.cancel();
      liveDebtTimer = Timer(const Duration(milliseconds: 500), _syncLiveDebt);
    } catch (e) {
      print('schedule live sync error: $e');
    }
  }

  // ⚠️ حُذفت _persistPaymentTypeLightweight.
  //
  // كانت تكتب amount_paid_on_invoice في جدول الفواتير بلا أي معاملة دين
  // مقابلة، فتُحدث فرقاً دائماً بين الفاتورة وسجل الديون. لم تكن مستدعاة من
  // أي مكان (كود ميت)، لكنها بقيت قنبلة لمن يربطها بزر لاحقاً.
  // المبلغ المسدد لا يُكتب إلا من saveInvoice، ومعه الحارس المحاسبي.

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎨 Helper: بناء صف إجمالي
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildTotalRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        Text('$value د.ع', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎨 الشريط الجانبي: المجاميع، الدفع، والإجراءات
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSidebar(BuildContext context) {
    // ✅ Always show sidebar - removed placeholder message per user request

    final totalBeforeDiscount = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final total = totalBeforeDiscount - discount;
    double enteredPaidAmount = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0;
    
    // حساب التسويات
    final double cashSettlements = _invoiceAdjustments
        .where((a) => (a.settlementPaymentType ?? 'نقد') == 'نقد')
        .fold(0.0, (sum, a) => sum + a.amountDelta);
        
    final double debtSettlements = _invoiceAdjustments
        .where((a) => a.settlementPaymentType == 'دين')
        .fold(0.0, (sum, a) => sum + a.amountDelta);

    final double totalAfterAdjustments = total + (_invoiceAdjustments.isNotEmpty ? _totalSettlementAmount : 0.0);
    
    double displayedPaidAmount = enteredPaidAmount;
    double displayedRemainingAmount = totalAfterAdjustments - displayedPaidAmount;

    if (paymentType == 'نقد') {
      displayedPaidAmount = totalAfterAdjustments;
      displayedRemainingAmount = 0;
    } else {
      displayedPaidAmount = enteredPaidAmount + cashSettlements;
      displayedRemainingAmount = totalAfterAdjustments - displayedPaidAmount;
    }
    
    // إضافة أجور التحميل
    double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
    final totalWithLoading = total + loadingFee;
    final totalAfterAdjustmentsWithLoading = totalWithLoading + (_invoiceAdjustments.isNotEmpty ? _totalSettlementAmount : 0.0);
    
    if (paymentType == 'نقد') {
        displayedPaidAmount = totalAfterAdjustmentsWithLoading;
    } else {
        displayedRemainingAmount = totalAfterAdjustmentsWithLoading - displayedPaidAmount;
    }

    // ألوان التصميم الجديد
    const Color headerColor = Color(0xFF2D3748); // Dark blue-gray
    const Color bgColor = Color(0xFFF7FAFC); // Light gray background
    
    return Container(
      color: bgColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 🧱 رصيد العميل وسقف دينه وحسمه + حقول إضافية/مرتجع للفاتورة المحفوظة
            ErpInvoiceSidePanel(
              customerName: customerNameController.text,
              invoiceTotal: total,
              isDebt: paymentType == 'دين',
              invoiceId: invoiceToManage?.status == 'محفوظة' ? invoiceToManage?.id : null,
            ),
            // ═══════════════════════════════════════════════════════════════
            // 1. تفاصيل الإجماليات (داخل الـ ScrollView لتصعد للأعلى عند السحب)
            // ═══════════════════════════════════════════════════════════════
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // الإجمالي قبل الخصم
                  _buildTotalRow('الإجمالي قبل الخصم', formatNumber(totalBeforeDiscount), Colors.grey[700]!),
                  const Divider(height: 16),
                  // الإجمالي بعد الخصم
                  _buildTotalRow('الإجمالي بعد الخصم', formatNumber(total), Colors.blue[700]!),
                  const Divider(height: 16),
                  // المبلغ المسدد
                  _buildTotalRow('المبلغ المسدد', formatNumber(displayedPaidAmount), Colors.green[700]!),
                  const Divider(height: 16),
                  // المبلغ المتبقي
                  _buildTotalRow('المبلغ المتبقي', formatNumber(displayedRemainingAmount), 
                      displayedRemainingAmount > 0 ? Colors.red[700]! : Colors.green[700]!),
                ],
              ),
            ),
    
                  
                  // أجور التحميل (إذا كانت مفعّلة)
                  if (!isViewOnly && !(invoiceToManage?.isLocked ?? false)) ...[
                    _buildStyledInputField(
                      controller: loadingFeeController,
                      label: 'أجور التحميل والنقل',
                      icon: Icons.local_shipping_outlined,
                      onChanged: (val) {
                        setState(() {
                          _guardDiscount();
                          _updatePaidAmountIfCash(); 
                          _calculateProfit();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // الخصم المسموح
                  _buildStyledInputField(
                    controller: discountController,
                    label: 'الخصم المسموح',
                    icon: Icons.local_offer_outlined,
                    enabled: !isViewOnly,
                    showWarningIcon: true,
                    onChanged: (val) {
                      setState(() {
                        discount = double.tryParse(val.replaceAll(',', '')) ?? 0.0;
                        _guardDiscount();
                        _updatePaidAmountIfCash();
                        _calculateProfit();
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  // طريقة الدفع
                  if (!isViewOnly) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  paymentType = 'نقد';
                                  _updatePaidAmountIfCash();
                                  _autoSave();
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: paymentType == 'نقد' ? const Color(0xFFE6F7F2) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                                  border: paymentType == 'نقد' 
                                    ? Border.all(color: const Color(0xFF48BB78), width: 1.5)
                                    : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.attach_money, 
                                      color: paymentType == 'نقد' ? const Color(0xFF48BB78) : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text('نقد',
                                      style: TextStyle(
                                        color: paymentType == 'نقد' ? const Color(0xFF48BB78) : Colors.grey.shade700,
                                        fontWeight: paymentType == 'نقد' ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (paymentType == 'نقد')
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.check, color: Color(0xFF48BB78), size: 16),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  paymentType = 'دين';
                                  paidAmountController.text = formatNumber(0);
                                  _autoSave();
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: paymentType == 'دين' ? const Color(0xFFE8F4FD) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                                  border: paymentType == 'دين' 
                                    ? Border.all(color: const Color(0xFF4299E1), width: 1.5)
                                    : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.account_balance_wallet_outlined, 
                                      color: paymentType == 'دين' ? const Color(0xFF4299E1) : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text('دين',
                                      style: TextStyle(
                                        color: paymentType == 'دين' ? const Color(0xFF4299E1) : Colors.grey.shade700,
                                        fontWeight: paymentType == 'دين' ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (paymentType == 'دين')
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.check, color: Color(0xFF4299E1), size: 16),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // المبلغ الواصل (المدفوع) - يظهر فقط في حالة الدين
                    if (paymentType == 'دين') ...[
                      Text('المبلغ الواصل (المدفوع)', 
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(Icons.check_circle_outline, color: Colors.grey, size: 20),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: paidAmountController,
                                decoration: const InputDecoration(
                                  hintText: '0',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(vertical: 16),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                                textAlign: TextAlign.left,
                                style: const TextStyle(fontSize: 16),
                                onChanged: (val) => setState(() {}),
                              ),
                            ),
                            // زر تسديد كامل المبلغ
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  paidAmountController.text = formatNumber(totalAfterAdjustmentsWithLoading);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('%100', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                  
                  // المتبقي على العميل (يظهر دائماً في حالة الدين)
                  if (paymentType == 'دين')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFF5F5), Color(0xFFFED7D7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFEB2B2), width: 1),
                      ),
                      child: Column(
                        children: [
                          Text('المتبقي على العميل', 
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                formatNumber(displayedRemainingAmount),
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('د.ع', 
                                style: TextStyle(color: Colors.red.shade500, fontSize: 14)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  // 3. زر الحفظ في الأسفل
                  if (!isViewOnly) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : saveInvoice,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF48BB78), // Green
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.save_alt, size: 22),
                        label: const Text('حفظ الفاتورة', 
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
  
  // Helper: Info Row (Label + Value)
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
  
  // Helper: Styled Input Field
  Widget _buildStyledInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
    bool showWarningIcon = false,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            if (showWarningIcon) ...[
              const SizedBox(width: 4),
              Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber.shade700),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(icon, color: Colors.grey.shade400, size: 20),
              ),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    hintText: '0',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                  textAlign: TextAlign.left,
                  style: const TextStyle(fontSize: 16),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductEntryBar(BuildContext context) {
      if (isViewOnly) return const SizedBox.shrink();
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4), // Very light green
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
            children: [
                // 1. البحث عن صنف
                Expanded(
                  flex: 1,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            Text('البحث عن صنف', 
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            const SizedBox(height: 4),
                            Stack(
                              children: [
                                SizedBox(
                                    height: 48,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return RawAutocomplete<Product>(
                                            focusNode: _searchFocusNode,
                                            textEditingController: _productSearchController,
                                            optionsBuilder: (TextEditingValue textEditingValue) async {
                                                final query = textEditingValue.text;
                                                if (query.isEmpty) return const Iterable<Product>.empty();
                                                
                                                bool isNumeric = double.tryParse(query) != null;
                                                
                                                if (isNumeric) {
                                                    return await DatabaseService().searchProductsByIdPrefix(query);
                                                } else {
                                                    final currentNames = invoiceItems
                                                        .where((it) => it.productName.trim().isNotEmpty)
                                                        .map((it) => it.productName.trim())
                                                        .toList();
                                                    return await SmartSearchService.instance.smartSearch(
                                                      query,
                                                      currentInvoiceProductNames: currentNames,
                                                    );
                                                }
                                            },
                                            displayStringForOption: (Product p) => p.name,
                                            optionsViewBuilder: (context, onSelected, options) {
                                                return Align(
                                                    alignment: Alignment.topRight,
                                                    child: Material(
                                                        elevation: 8,
                                                        borderRadius: BorderRadius.circular(12),
                                                        // 🔧 اللون على الـ Material نفسه — DecoratedBox فوقه
                                                        // كان يحجب خلفية ListTile ورشّ الحبر (assertion)
                                                        color: Colors.white,
                                                        child: Container(
                                                            width: constraints.maxWidth,
                                                            constraints: const BoxConstraints(maxHeight: 300),
                                                            child: ListView.builder(
                                                                shrinkWrap: true,
                                                                itemCount: options.length,
                                                                itemBuilder: (context, index) {
                                                                    final product = options.elementAt(index);
                                                                    return ListTile(
                                                                        title: Text(product.name, 
                                                                            style: const TextStyle(fontWeight: FontWeight.w600)),
                                                                        subtitle: Row(
                                                                          children: [
                                                                            Text(
                                                                                'السعر: ${formatNumber(product.price1)} | المخزون: ${product.stockQuantity}',
                                                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                                                            if ((product.stockQuantity ?? 0) <= 0)
                                                                              const Padding(
                                                                                padding: EdgeInsets.only(right: 6),
                                                                                child: Tooltip(
                                                                                  message: 'غير متوفر في المخزون',
                                                                                  child: Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                                                                                ),
                                                                              ),
                                                                          ],
                                                                        ),
                                                                        leading: CircleAvatar(
                                                                            radius: 18,
                                                                            backgroundColor: const Color(0xFFE6F7F2),
                                                                            child: Text('#${product.id}', 
                                                                                style: const TextStyle(fontSize: 10, color: Color(0xFF48BB78), fontWeight: FontWeight.bold)),
                                                                        ),
                                                                        onTap: () => onSelected(product),
                                                                    );
                                                                },
                                                            ),
                                                        ),
                                                    ),
                                                );
                                            },
                                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                                return Container(
                                                    decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(24),
                                                        boxShadow: [
                                                            BoxShadow(
                                                                color: Colors.black.withOpacity(0.05),
                                                                blurRadius: 8,
                                                                offset: const Offset(0, 2),
                                                            ),
                                                        ],
                                                    ),
                                                    child: TextField(
                                                        controller: controller,
                                                        focusNode: focusNode,
                                                        decoration: const InputDecoration(
                                                            hintText: 'أدخل اسم المنتج أو الرمز...',
                                                            hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                                                            prefixIcon: Icon(Icons.search, color: Colors.grey),
                                                            border: InputBorder.none,
                                                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                                        ),
                                                        textAlign: TextAlign.right,
                                                        style: const TextStyle(fontSize: 14),
                                                        onChanged: (val) {
                                                            _validateEntryStockByManualName(val); // 🔍 تحقق عند كل تغييرة
                                                        },
                                                        onSubmitted: (val) {
                                                            _validateEntryStockByManualName(val); // 🔍 تحقق نهائي
                                                            if (!_isEntryLocked) {
                                                                _quantityFocusNode.requestFocus();
                                                            }
                                                        },
                                                    ),
                                                );
                                            },
                                            onSelected: (Product selection) {
                                                _onProductSelected(selection);
                                            },
                                        );
                                      }
                                    ),
                                ),
                                if (_isEntryLocked)
                                  const Positioned(
                                    left: 45,
                                    top: 14,
                                    child: Icon(Icons.block, color: Colors.red, size: 20),
                                  ),
                              ],
                            ),
                        ],
                    ),
                ),
                const SizedBox(width: 16),

                // 2. الكمية
                _buildEntryField(
                    label: 'العدد',
                    width: 100, 
                    controller: _quantityController,
                    focusNode: _quantityFocusNode,
                    enabled: !_isEntryLocked, 
                    initialValue: '1',
                    onSubmitted: () {
                      // 🔧 Fix: فتح قائمة الوحدات إذا كان هناك أكثر من وحدة
                      if (currentUnitOptions.length > 1) {
                         _showUnitSelectionForEntryBar();
                      } else {
                         _priceFocusNode.requestFocus();
                      }
                    },
                ),
                const SizedBox(width: 12),

                // 2.5. نوع الوحدة
                Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Text('الوحدة', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 4),
                        Container(
                            key: _entryBarUnitDropdownKey, // 🔧 مفتاح لجلب موقع القائمة
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                    value: currentUnitOptions.contains(selectedUnitForItem) 
                                        ? selectedUnitForItem 
                                        : (currentUnitOptions.isNotEmpty ? currentUnitOptions.first : 'قطعة'),
                                    items: (currentUnitOptions.isEmpty ? ['قطعة'] : currentUnitOptions)
                                        .map((unit) => DropdownMenuItem(
                                            value: unit,
                                            child: Text(unit, style: const TextStyle(fontSize: 14)),
                                        ))
                                        .toList(),
                                    onChanged: _isEntryLocked ? null : (value) {
                                        if (value != null) {
                                            print('🔍 [تشخيص-تغيير-وحدة-شريط] "$value" '
                                                '(السابقة: $selectedUnitForItem) للمنتج: ${_selectedProduct?.name}');
                                            print('    السعر قبل التغيير: ${_priceController.text}');
                                            setState(() {
                                                selectedUnitForItem = value;
                                                if (_selectedProduct != null) {
                                                    _updatePriceForSelectedProduct(_selectedProduct!);
                                                }
                                            });
                                        }
                                    },
                                ),
                            ),
                        ),
                    ],
                ),
                const SizedBox(width: 12),
                
                // 3. السعر (مع تحذير التكلفة)
                _buildPriceEntryFieldWithWarning(),
                const SizedBox(width: 12),
                
                // 4. زر الإضافة
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: _isEntryLocked ? Colors.grey : const Color(0xFF48BB78), 
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                              if (!_isEntryLocked)
                                BoxShadow(
                                    color: const Color(0xFF48BB78).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                ),
                          ],
                      ),
                      child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _isEntryLocked ? null : _addInvoiceItem, 
                              child: const Center(
                                  child: Icon(Icons.add, color: Colors.white, size: 28),
                              ),
                          ),
                      ),
                  ),
                ),
            ],
        ),
      );
  }
  
  // 🔧 دالة لفتح قائمة الوحدات في شريط البحث العلوي (مشابهة لـ _showSaleTypeMenu في EditableInvoiceItemRow)
  Future<void> _showUnitSelectionForEntryBar() async {
    if (currentUnitOptions.length <= 1) {
      _priceFocusNode.requestFocus();
      return;
    }

    final RenderBox? renderBox = _entryBarUnitDropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      _priceFocusNode.requestFocus();
      return;
    }

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    // فتح قائمة منبثقة مع دعم الكيبورد
    final String? selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext dialogContext) {
        return _SaleTypeDropdownDialog(
          options: currentUnitOptions,
          initialValue: selectedUnitForItem,
          position: offset,
          size: size,
        );
      },
    );

    if (selected != null && selected != selectedUnitForItem) {
      setState(() {
        selectedUnitForItem = selected;
        if (_selectedProduct != null) {
          _updatePriceForSelectedProduct(_selectedProduct!);
        }
      });
    }

    // الانتقال لحقل السعر بعد الاختيار
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _priceFocusNode.requestFocus();
    });
  }

  // 🔧 Fix 3: Helper method للتحقق من أن السعر أقل من التكلفة
  // 🔧 تم إعادة كتابة هذه الدالة لتستخدم نفس منطق _isPriceBelowCost في الصفوف
  bool _isEntryPriceBelowCost() {
    if (_selectedProduct == null) return false;
    
    final double enteredPrice = double.tryParse(_priceController.text.replaceAll(',', '')) ?? 0;
    if (enteredPrice <= 0) return false;
    
    double? effectiveCostPerUnit;
    final product = _selectedProduct!;
    final String saleType = selectedUnitForItem;
    
    // جرب من unit_costs أولاً
    try {
      final Map<String, double> unitCosts = product.getUnitCostsMap();
      if (unitCosts.containsKey(saleType) && unitCosts[saleType]! > 0) {
        effectiveCostPerUnit = unitCosts[saleType];
      }
    } catch (_) {}
    
    // ثم من costPrice الأساسي للمنتج مع حساب المضاعف من الهرمية
    if (effectiveCostPerUnit == null && product.costPrice != null && product.costPrice! > 0) {
      // إذا كان البيع بالوحدة الأساسية
      if ((product.unit == 'piece' && saleType == 'قطعة') ||
          (product.unit == 'meter' && saleType == 'متر')) {
        effectiveCostPerUnit = product.costPrice;
      }
      // للمتر و"لفة": استخدم طول اللفة
      else if (product.unit == 'meter' && saleType == 'لفة') {
        final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
        effectiveCostPerUnit = product.costPrice! * lengthPerUnit;
      }
      // إذا كان البيع بوحدة كبيرة، احسب التكلفة من الهرمية
      else if (saleType != 'قطعة' && saleType != 'متر') {
        double multiplier = 1.0;
        
        // 🔧 Fix: استخدام unitHierarchy للحساب الصحيح
        if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
          try {
            // محاولة تحليل JSON مع دعم علامات الاقتباس المفردة والمزدوجة
            List<dynamic> hierarchy;
            try {
              hierarchy = json.decode(product.unitHierarchy!);
            } catch (_) {
              hierarchy = json.decode(product.unitHierarchy!.replaceAll("'", '"'));
            }

            for (final level in hierarchy) {
              final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
              final double qty = (level['quantity'] is num)
                  ? (level['quantity'] as num).toDouble()
                  : double.tryParse(level['quantity'].toString()) ?? 1.0;
              multiplier *= qty;
              if (unitName == saleType) break;
            }
          } catch (_) {
            // استخدام المضاعف المحسوب من currentUnitOptions إذا توفر
            // fallback: ابحث في الهرمية المحفوظة
            for (final unitInfo in _currentUnitHierarchy) {
              if (unitInfo['unit_name'] == saleType || unitInfo['name'] == saleType) {
                multiplier = (unitInfo['quantity'] as num?)?.toDouble() ?? 1.0;
                break;
              }
            }
          }
        } else {
          // fallback: ابحث في الهرمية المحفوظة
          for (final unitInfo in _currentUnitHierarchy) {
            if (unitInfo['unit_name'] == saleType || unitInfo['name'] == saleType) {
              multiplier = (unitInfo['quantity'] as num?)?.toDouble() ?? 1.0;
              break;
            }
          }
        }
        
        effectiveCostPerUnit = product.costPrice! * multiplier;
      }
    }
    
    if (effectiveCostPerUnit == null || effectiveCostPerUnit <= 0) return false;
    
    const double eps = 1e-6;
    return (enteredPrice + eps) < effectiveCostPerUnit;
  }
  
  // 🔧 Fix 3: Price field with warning icon
  Widget _buildPriceEntryFieldWithWarning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('السعر', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            // 🧱 أدوات سريعة (مثل الإداري): حسم % على السطر، هدية مجانية، الإجمالي ⇐ السعر
            if (!_isEntryLocked) ...[
              const SizedBox(width: 4),
              _entryTool(Icons.percent, 'حسم % على هذا الصنف', _applyEntryDiscount),
              _entryTool(Icons.card_giftcard, 'هدية مجانية (سعر صفر)', () => setState(() => _priceController.text = '0')),
              _entryTool(Icons.functions, 'أدخل الإجمالي ليُحسب السعر', _applyEntryTotal),
            ],
            if (_isEntryPriceBelowCost()) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'السعر أقل من التكلفة!',
                child: Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber.shade700),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: 130,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: _isEntryPriceBelowCost() 
                ? Border.all(color: Colors.amber.shade700, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextFormField(
            controller: _priceController,
            focusNode: _priceFocusNode,
            enabled: !_isEntryLocked,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            onChanged: (_) => setState(() {}), // Trigger rebuild for warning
            onFieldSubmitted: (_) {
              _addInvoiceItem();
              _searchFocusNode.requestFocus();
            },
          ),
        ),
      ],
    );
  }

  // 🧱 أدوات شريط الإدخال (تعدّل حقل السعر فقط — الحفظ بالمسار الأصلي)
  Widget _entryTool(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon, size: 15, color: Colors.blueGrey.shade600),
          ),
        ),
      );

  Future<void> _applyEntryDiscount() async {
    final price = double.tryParse(_priceController.text.replaceAll(',', '')) ?? 0;
    if (price <= 0) return;
    final pct = await askNumber(context, 'حسم % على سعر هذا الصنف', label: 'النسبة %');
    if (pct == null || pct <= 0 || pct >= 100) return;
    final newPrice = (price * (1 - pct / 100) * 100).roundToDouble() / 100;
    setState(() => _priceController.text = formatNumber(newPrice));
  }

  Future<void> _applyEntryTotal() async {
    final qty = safeParseDouble(_quantityController.text) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل الكمية أولاً')));
      return;
    }
    final total = await askNumber(context, 'الإجمالي المطلوب لهذا الصنف', label: 'الإجمالي');
    if (total == null || total < 0) return;
    final newPrice = (total / qty * 100).roundToDouble() / 100;
    setState(() => _priceController.text = formatNumber(newPrice));
  }

  // Helper: Entry Field with label
  Widget _buildEntryField({
    required String label,
    required double width,
    required TextEditingController controller,
    FocusNode? focusNode,
    String? initialValue,
    bool enabled = true, // 🔒 Added enabled parameter
    VoidCallback? onSubmitted,
  }) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Container(
                width: width,
                height: 48,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                        ),
                    ],
                ),
                child: TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled, // 🔒 Use enabled status
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    onFieldSubmitted: (_) => onSubmitted?.call(),
                ),
            ),
        ],
    );
  }

  // Helper method to update price based on selected list type AND selected unit (with Smart Pricing)
  Future<void> _updatePriceForSelectedProduct(Product product) async {
      double? basePrice;
      switch (_selectedListType) {
          case 'مفرد':
              basePrice = product.price1;
              break;
          case 'مفرد 2':
              basePrice = product.price2;
              break;
          case 'منزل':
              basePrice = product.price3;
              break;
          case 'جملة':
              basePrice = product.price4;
              break;
          case 'جملة 2':
              basePrice = product.price5;
              break;
          case 'أخرى':
              basePrice = product.price6;
              break;
          default:
              basePrice = product.price1;
      }
      
      // 🧠 استشارة محرك التسعير الذكي عند إدخال صنف من جدول الفاتورة
      if (product.id != null) {
        try {
          int? custId;
          final custName = customerNameController.text.trim();
          if (custName.isNotEmpty) {
            final c = await db.findCustomerByNormalizedName(custName);
            if (c != null) custId = c.id;
          }
          final smartResult = await SmartPricingService().getSmartPriceEnhanced(
            productId: product.id!,
            customerId: custId,
            saleType: _selectedListType,
          );
          if (smartResult != null && smartResult.price > 0) {
            basePrice = smartResult.price;
            print('    🧠 [تشخيص-تحديث-سعر] التسعير الذكي استبدل السعر الأساسي: ${smartResult.price} (سيُضرب بالمضاعف إن وُجد)');
          }
        } catch (_) {}
      }
      
      if (basePrice == null || basePrice <= 0) {
          _priceController.clear();
          _selectedPriceLevel = null;
          print('🔍 [تشخيص-تحديث-سعر] لا سعر أساسي — تم تفريغ الحقل (basePrice=$basePrice)');
          return;
      }

      // 🔍 تشخيص تحويل الوحدات — قرار السعر بوحدة "$selectedUnitForItem"
      print('🔍 [تشخيص-تحديث-سعر] "${product.name}" | unit="${product.unit}" | الوحدة المختارة: "$selectedUnitForItem"');
      print('    basePrice=$basePrice (قائمة: $_selectedListType) | translatedUnit="${product.translatedUnit}"');
      print('    unitHierarchy=${product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty ? "موجودة (${product.unitHierarchy!.length} حرف)" : "فارغة/عدم"}');

      // 🔧 Fix 2: حساب السعر بناءً على الوحدة المختارة
      double finalPrice = basePrice;

      // إذا كانت الوحدة المختارة ليست الوحدة الأساسية
      if (selectedUnitForItem != product.translatedUnit && selectedUnitForItem != 'قطعة') {
          // للمتر واللفة
          if (product.unit == 'meter' && selectedUnitForItem == 'لفة') {
              final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
              finalPrice = basePrice * lengthPerUnit;
              print('    ↪ فرع متر→لفة: ×$lengthPerUnit → $finalPrice');
          }
          // للقطعة مع هرمية الوحدات
          // 🔧 Fix: Robust JSON parsing
          else if (product.unit == 'piece' && product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
              try {
                  List<dynamic> hierarchy;
                  try {
                    hierarchy = json.decode(product.unitHierarchy!);
                  } catch (_) {
                    hierarchy = json.decode(product.unitHierarchy!.replaceAll("'", '"'));
                  }

                  double multiplier = 1.0;
                  for (final level in hierarchy) {
                      final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                      final double qty = (level['quantity'] is num)
                          ? (level['quantity'] as num).toDouble()
                          : double.tryParse(level['quantity'].toString()) ?? 1.0;
                      multiplier *= qty;
                      if (unitName == selectedUnitForItem) {
                          break;
                      }
                  }
                  finalPrice = basePrice * multiplier;
                  print('    ↪ فرع الهرمية: مضاعف=$multiplier → السعر=$finalPrice');
              } catch (e) {
                  print('    ↪ ❌ فشل حساب الهرمية: $e (السعر بقي $finalPrice)');
                  print('خطأ في حساب السعر الهيراركي: $e');
              }
          } else {
              // 🔍 هذا هو الفرع المشبوه: وحدة غير أساسية لكن لا meter ولا piece
              print('    ↪ ⚠️ لا فرع تحويل: unit="${product.unit}" ليست piece/meter '
                  '→ السعر بقي كما هو ($finalPrice) — هذا سبب خطأ الموزونات');
          }
      } else {
          print('    ↪ الوحدة المختارة هي الأساسية — السعر بلا تحويل: $finalPrice');
      }

      _priceController.text = formatNumber(finalPrice);
      _selectedPriceLevel = finalPrice;
      print('    ✅ السعر النهائي المكتوب في الحقل: $finalPrice');
  }

  @override
  Widget build(BuildContext context) {
    // تعريف الألوان والثيم العصري
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo
    final Color accentColor = const Color(0xFF8C9EFF); // Light Indigo Accent
    final Color textColor = const Color(0xFF212121);
    final Color lightBackgroundColor = const Color(0xFFF8F8F8);
    final Color successColor = Colors.green[600]!;
    final Color errorColor = Colors.red[700]!;

    // استخدم القائمة الكاملة دائمًا لعرض جميع الصفوف بما في ذلك الصف الفارغ الجديد
    final displayedItems = invoiceItems;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Theme(
        data: ThemeData(
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: accentColor,
          onSecondary: Colors.black,
          surface: Colors.white,
          onSurface: textColor,
          background: Colors.white,
          onBackground: textColor,
          error: errorColor,
          onError: Colors.white,
          tertiary: successColor,
        ),
        fontFamily: 'Roboto',
        textTheme: TextTheme(
          titleLarge: TextStyle(
              fontSize: 22.0, fontWeight: FontWeight.bold, color: Colors.white),
          titleMedium: TextStyle(
              fontSize: 18.0, fontWeight: FontWeight.w600, color: textColor),
          bodyLarge: TextStyle(fontSize: 16.0, color: textColor),
          bodyMedium: TextStyle(fontSize: 14.0, color: textColor),
          labelLarge: TextStyle(
              fontSize: 16.0, color: Colors.white, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(fontSize: 14.0, color: Colors.grey[600]),
          bodySmall: TextStyle(fontSize: 12.0, color: Colors.grey[700]),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: primaryColor, width: 2.0),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          labelStyle: TextStyle(color: Colors.grey[700], fontSize: 15.0),
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14.0),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
          filled: true,
          fillColor: lightBackgroundColor,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0)),
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            elevation: 4,
            textStyle: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
        cardTheme: CardThemeData(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          margin: EdgeInsets.zero,
        ),
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: lightBackgroundColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF212121),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 4,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      child: Stack(
        children: [
          // المحتوى الرئيسي
          AbsorbPointer(
            absorbing: isSaving,
            child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 60, // 🔺 Increased height for better visibility
          title: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                     // 1. Customer Name (Autocomplete)
                    SizedBox(
                      width: 250, // Fixed width for scrollable layout
                      height: 42, // 🔺 Increased Height for better visibility
                      child: Autocomplete<String>(
                        optionsBuilder: (TextEditingValue textEditingValue) async {
                          if (textEditingValue.text == '') {
                            return const Iterable<String>.empty();
                          }
                          final customers = await db.searchCustomers(textEditingValue.text);
                          return customers.map((c) => c.name).toSet();
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (controller.text != customerNameController.text) {
                              controller.text = customerNameController.text;
                              controller.selection = TextSelection.fromPosition(
                                TextPosition(offset: controller.text.length),
                              );
                            }
                          });
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            enabled: !isViewOnly,
                            style: const TextStyle(color: Colors.white, fontSize: 12.5), // 🔻 Smaller Font
                            decoration: InputDecoration(
                              hintText: 'اسم العميل',
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                              prefixIcon: Icon(Icons.person_outline, color: Colors.white54, size: 18),
                              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 0),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.12),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), // 🔻 Rounded
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white30, width: 0.5)),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'مطلوب';
                              }
                              return null;
                            },
                            onChanged: (val) {
                              customerNameController.text = val;
                              _onFieldChanged();
                              if (invoiceToManage != null &&
                                  invoiceToManage!.status == 'معلقة' &&
                                  (invoiceToManage?.isLocked ?? false)) {
                                autoSaveSuspendedInvoice();
                              }
                            },
                          );
                        },
                        onSelected: (String selection) async {
                          // 🔒 [Locking System] Verify Customer Lock
                          final selectedCustomer = await db.findCustomerByNormalizedName(selection);
                          if (selectedCustomer != null && selectedCustomer.id != null) {
                             final isLocked = await db.lockingService.isLockedByOther(
                               resourceType: 'customer', 
                               resourceId: selectedCustomer.id!
                             );
                             
                             if (isLocked) {
                               if (context.mounted) {
                                 ScaffoldMessenger.of(context).showSnackBar(
                                   const SnackBar(
                                     content: Text('⚠️ هذا العميل قيد الاستخدام من قبل مستخدم آخر!'),
                                     backgroundColor: Colors.orange,
                                     duration: Duration(seconds: 4),
                                   ),
                                 );
                                 // Clear selection
                                 customerNameController.clear();
                                 return;
                               }
                             }
                             
                             // Attempt to acquire lock for ourselves
                             if (context.mounted) {
                                final lockResult = await db.lockingService.acquireLock(
                                  resourceType: 'customer',
                                  resourceId: selectedCustomer.id!
                                );
                                if (!lockResult.success) {
                                   // Double check fail (race condition)
                                   customerNameController.clear();
                                   if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                       SnackBar(content: Text(lockResult.message ?? 'فشل حجز العميل')),
                                     );
                                   }
                                   return; 
                                }
                             }
                          }

                          customerNameController.text = selection;
                          _onFieldChanged();
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topRight,
                            child: Material(
                              elevation: 4.0,
                              color: const Color(0xFF333333), // Darker dropdown
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                height: 200.0,
                                width: constraints.maxWidth * 0.3,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(4.0),
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final String option = options.elementAt(index);
                                    return GestureDetector(
                                      onTap: () {
                                        onSelected(option);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                        decoration: const BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
                                        ),
                                        child: Text(option, style: const TextStyle(color: Colors.white)),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(width: 8),

                  // 2. Phone
                  SizedBox(
                    width: 180, // 🔺 Increased further per user request
                    height: 42, // 🔺 Increased Height
                    child: TextFormField(
                      controller: customerPhoneController,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5),
                      keyboardType: TextInputType.phone,
                      enabled: !isViewOnly,
                      decoration: InputDecoration(
                        hintText: 'الجوال',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                        prefixIcon: Icon(Icons.phone_outlined, color: Colors.white54, size: 18),
                        prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.12),
                         contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                         isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white30, width: 0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Address
                   SizedBox(
                      width: 200, // Fixed width for scrollable layout
                      height: 42, // 🔺 Increased Height for better visibility
                      child: TextFormField(
                        controller: customerAddressController,
                         style: const TextStyle(color: Colors.white, fontSize: 12.5),
                        enabled: !isViewOnly,
                        decoration: InputDecoration(
                          hintText: 'العنوان',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                          prefixIcon: Icon(Icons.location_on_outlined, color: Colors.white54, size: 18),
                          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.12),
                           contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                           isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white30, width: 0.5)),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),

                  // 3.5. اسم المستخدم الحالي (الكاشير/المحاسب)
                  Builder(
                    builder: (context) {
                      final username = AuthService().currentUser?.username ?? 'غير معروف';
                      return Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person, color: Colors.white54, size: 16),
                            const SizedBox(width: 6),
                            Text(username, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),

                   // 4. Date Picker
                  InkWell(
                    onTap: isViewOnly ? null : () => _selectDate(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 42, // 🔺 Increased Height
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.transparent),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('yyyy-MM-dd').format(selectedDate),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.normal, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.calendar_today, color: Colors.white70, size: 15),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // 5. نوع القائمة (مفرد/جملة/إلخ) - في الـ AppBar
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('نوع الفاتورة', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(width: 8),
                      Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedListType,
                        dropdownColor: const Color(0xFF333333),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                        items: const [
                          DropdownMenuItem(value: 'مفرد', child: Text('مفرد', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'مفرد 2', child: Text('مفرد 2', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'منزل', child: Text('منزل', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'جملة', child: Text('جملة', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'جملة 2', child: Text('جملة 2', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'أخرى', child: Text('أخرى', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: isViewOnly ? null : (value) {
                          setState(() {
                            _selectedListType = value ?? 'مفرد';
                            if (_selectedProduct != null) {
                              _updatePriceForSelectedProduct(_selectedProduct!);
                            }
                          });
                        },
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                  ),
                  ], // close Row children (نوع الفاتورة)
                ), // close Row (نوع الفاتورة)
              ], // close Main Row children
            ), // close Main Row
          ); // close SingleChildScrollView
            }
          ),
          centerTitle: true,
          actions: [
            // زر جديد لإعادة التعيين - يظهر دائماً per user request
            IconButton(
              icon: const Icon(Icons.receipt),
              tooltip: 'فاتورة جديدة',
              onPressed: invoiceItems.isNotEmpty ||
                      customerNameController.text.isNotEmpty
                  ? _resetInvoice
                  : null,
            ),
            // زر الطباعة الموجود
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'طباعة الفاتورة',
              onPressed: (invoiceItems.isEmpty || isSaving) ? null : printInvoice,
            ),
            IconButton(
              icon: const Icon(Icons.print_disabled),
              tooltip: 'طباعة تجهيز (بدون أسعار)',
              onPressed: (invoiceItems.isEmpty || isSaving) ? null : _printPickingList,
            ),
            // زر المشاركة الجديد
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'مشاركة الفاتورة PDF',
              onPressed: (invoiceItems.isEmpty || isSaving) ? null : shareInvoice,
            ),
            // 📋 زر سجل التعديلات
            if (invoiceToManage != null) 
              FutureBuilder<bool>(
                future: DatabaseService().hasInvoiceBeenModified(invoiceToManage!.id!),
                builder: (context, snapshot) {
                  final hasHistory = snapshot.data ?? false;
                  return IconButton(
                    icon: Icon(
                      Icons.history,
                      color: hasHistory ? Colors.orange : null,
                    ),
                    tooltip: hasHistory ? 'سجل التعديلات (تم التعديل)' : 'سجل التعديلات',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InvoiceHistoryScreen(
                            invoiceId: invoiceToManage!.id!,
                            customerName: customerNameController.text,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            if (invoiceToManage != null && isViewOnly) ...[
              if (invoiceToManage!.isCreatedByMe)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'تعديل الفاتورة',
                  onPressed: isSaving ? null : _enableEditMode,
                ),
              IconButton(
                icon: const Icon(Icons.playlist_add),
                tooltip: 'تسوية الفاتورة - تحت التطوير',
                onPressed: isSaving ? null : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('هذه الميزة تحت التطوير حالياً'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
            if (invoiceToManage != null && !isViewOnly) ...[
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'حفظ التعديلات',
                onPressed: isSaving ? null : saveInvoice,
              ),
              IconButton(
                icon: const Icon(Icons.cancel),
                tooltip: 'إلغاء التعديل',
                onPressed: isSaving ? null : _cancelEdit,
              ),
            ],
          ],
        ),
        body: Row(
          children: [
            if (_appSettings != null && AppSideNav.shouldShow(context, _appSettings!))
              const AppSideNav(currentRoute: '/create_invoice'),
            Expanded(
              child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;
            return Flex(
              direction: isDesktop ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ═══════════════════════════════════════════════════════════════════════════
                // 1. القسم الرئيسي (جدول المواد + شريط الإدخال) - يأخذ المساحة الأكبر
                // ═══════════════════════════════════════════════════════════════════════════
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                  // شريط إدخال المواد (أفقي) - يظهر فقط إذا لم يكن للعرض
                  _buildProductEntryBar(context),
                  
                  // رأس الجدول (Header Row)
                  if (invoiceItems.isNotEmpty || !isViewOnly)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10.0, horizontal: 8.0),
                      color: Colors.grey[200],
                      child: Row(
                        children: [
                          Expanded(
                              flex: 1,
                              child: Text('ت',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                                      
                          // ID Removed from here previously
                          
                          Expanded(
                              flex: 7,
                              child: Text('التفاصيل',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(
                              flex: 2,
                              child: Text('العدد',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(
                              flex: 2,
                              child: Text('نوع',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(
                              flex: 2,
                              child: Text('السعر',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          if (!isViewOnly)
                          Expanded(
                              flex: 2,
                              child: Text('وحدة', // Unit Count
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),

                          Expanded(
                              flex: 2,
                              child: Text('الإجمالي',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
const SizedBox(width: 120),
                        ],
                      ),
                    ),

                  // قائمة المواد (Table)
                  Expanded(
                    child: Form(
                      key: formKey,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: invoiceItems.length,
                        padding: const EdgeInsets.only(bottom: 100), // مساحة في الأسفل
                        itemBuilder: (context, index) {
                          final item = invoiceItems[index];

                          // Ensure focus nodes exist
                          while (focusNodesList.length <= index) {
                             focusNodesList.add(LineItemFocusNodes());
                          }

                          return EditableInvoiceItemRow(
                            key: ValueKey(item.uniqueId),
                            item: item,
                            index: index,
                            getCurrentInvoiceProductNames: () {
                              return invoiceItems
                                  .where((it) => it.productName.trim().isNotEmpty && it.uniqueId != item.uniqueId)
                                  .map((it) => it.productName.trim())
                                  .toList();
                            },
                            onItemUpdated: (updatedItem) {
                                if (invoiceToManage != null && !isViewOnly) {
                                  hasUnsavedChanges = true;
                                }
                                setState(() {
                                  final i = invoiceItems.indexWhere((it) => it.uniqueId == updatedItem.uniqueId);
                                  if (i != -1) {
                                    invoiceItems[i] = updatedItem;
                                  }
                                  _recalculateTotals();
                                  _calculateProfit();
                                });
                                _scheduleLiveDebtSync();
                            },
                            onItemRemovedByUid: _removeInvoiceItemByUid,
                            allProducts: _allProductsForUnits ?? [],
                            isViewOnly: isViewOnly,
                            isPlaceholder: false, 
                            
                            detailsFocusNode: !isViewOnly && index < focusNodesList.length ? focusNodesList[index].details : null,
                            quantityFocusNode: !isViewOnly && index < focusNodesList.length ? focusNodesList[index].quantity : null,
                            priceFocusNode: !isViewOnly && index < focusNodesList.length ? focusNodesList[index].price : null,
                            
                            databaseService: db,
                            currentCustomerName: customerNameController.text,
                            currentCustomerPhone: customerPhoneController.text,
                            allowNegativeStock: _allowNegativeStock, // مرر الإعداد هنا
                            onPriceSubmitted: () {
                                // إضافة صف فارغ جديد مباشرة (بدون التحقق من المنتج المحدد)
                                setState(() {
                                    invoiceItems.add(InvoiceItem(
                                        invoiceId: 0,
                                        productName: '',
                                        unit: '',
                                        unitPrice: 0,
                                        appliedPrice: 0,
                                        itemTotal: 0,
                                        uniqueId: 'row_${DateTime.now().microsecondsSinceEpoch}',
                                    ));
                                    
                                    // إضافة FocusNodes للصف الجديد
                                    focusNodesList.add(LineItemFocusNodes());
                                });
                                
                                // انتظر لحين بناء الـ widget الجديد ثم انقل التركيز
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted) {
                                        final newIndex = invoiceItems.length - 1;
                                        if (newIndex >= 0 && newIndex < focusNodesList.length) {
                                            focusNodesList[newIndex].details.requestFocus();
                                        }
                                    }
                                });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            
            // الفاصل العمودي
            isDesktop
                ? VerticalDivider(width: 1, color: Colors.grey.shade300)
                : Divider(height: 1, color: Colors.grey.shade300),

            // ═══════════════════════════════════════════════════════════════════════════
            // 2. الشريط الجانبي (Totals & Actions) - يأخذ المساحة الأقل
            // ═══════════════════════════════════════════════════════════════════════════
            Expanded(
              flex: isDesktop ? 1 : 2,
              child: _buildSidebar(context),
            ),
          ],
        );
      },
    ),
            ),
          ],
        ),
            ), // نهاية Scaffold
          ), // نهاية AbsorbPointer
          // ═══════════════════════════════════════════════════════════════════════════
          // 🔄 مؤشر التحميل أثناء الحفظ
          // ═══════════════════════════════════════════════════════════════════════════
          if (isSaving)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'جاري حفظ الفاتورة...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'يرجى الانتظار وعدم إغلاق التطبيق',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ], // نهاية Stack children
      ), // نهاية Stack
    ), // نهاية Theme
    ); // نهاية WillPopScope
  }

  Future<bool> _showAddAdjustmentDialog() async {
    if (invoiceToManage == null) return false;
    String type = 'debit';
    bool byItem = true;
    final TextEditingController productCtrl = TextEditingController();
    final TextEditingController qtyCtrl = TextEditingController();
    final TextEditingController priceCtrl = TextEditingController();
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    Product? selectedProduct;
    List<Product> productSuggestions = [];

    Future<void> fetchSuggestions(String q) async {
      // 🧠 استخدام البحث الذكي مع قائمة المنتجات الحالية
      final currentProductNames = invoiceItems
          .where((item) => item.productName.isNotEmpty)
          .map((item) => item.productName)
          .toList();
      productSuggestions = q.trim().isEmpty
          ? []
          : (await SmartSearchService.instance.smartSearch(
              q.trim(),
              currentInvoiceProductNames: currentProductNames,
            )).take(10).toList();
      if (mounted) setState(() {});
    }

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final double _maxH = MediaQuery.of(ctx).size.height * 0.7;
        return AlertDialog(
          title: const Text('إضافة تسوية على الفاتورة'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _maxH, minWidth: 320),
            child: SingleChildScrollView(
              child: StatefulBuilder(builder: (context, setLocal) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: type,
                      items: const [
                        DropdownMenuItem(value: 'debit', child: Text('إشعار مدين (زيادة)')),
                        DropdownMenuItem(value: 'credit', child: Text('إشعار دائن (نقص)')),
                      ],
                      onChanged: (v) => setLocal(() => type = v ?? 'debit'),
                      decoration: const InputDecoration(labelText: 'نوع التسوية'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('بند'),
                            selected: byItem,
                            onSelected: (s) => setLocal(() => byItem = true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('مبلغ مباشر'),
                            selected: !byItem,
                            onSelected: (s) => setLocal(() => byItem = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (byItem) ...[
                      TextField(
                        controller: productCtrl,
                        decoration: const InputDecoration(
                          labelText: 'المنتج',
                          hintText: 'اكتب اسم المنتج للبحث',
                        ),
                        onChanged: (v) async {
                          selectedProduct = null;
                          await fetchSuggestions(v);
                          setLocal(() {});
                        },
                      ),
                      if (productSuggestions.isNotEmpty)
                        // 🔧 اللون على Material بدل DecoratedBox فوقه (assertion ListTile)
                        Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          clipBehavior: Clip.antiAlias,
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: ListView.builder(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemCount: productSuggestions.length,
                            itemBuilder: (c, i) {
                              final p = productSuggestions[i];
                              return ListTile(
                                dense: true,
                                title: Text(p.name),
                                subtitle: Text('ID: ${p.id ?? ''}')
                                    ,
                                onTap: () {
                                  selectedProduct = p;
                                  productCtrl.text = p.name;
                                  productSuggestions = [];
                                  setLocal(() {});
                                },
                              );
                            },
                          ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'الكمية'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'السعر'),
                          ),
                        ),
                      ]),
                    ] else ...[
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'مبلغ التسوية'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
                    ),
                  ],
                );
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  double delta = 0;
                  int? productId;
                  String? productName;
                  double? qty;
                  double? price;
                  if (byItem) {
                    if (selectedProduct == null) {
                      throw 'اختر منتجاً';
                    }
                    qty = double.tryParse(qtyCtrl.text.trim());
                    price = double.tryParse(priceCtrl.text.trim());
                    if (qty == null || price == null) {
                      throw 'أدخل الكمية والسعر بشكل صحيح';
                    }
                    delta = (qty * price).toDouble();
                    productId = selectedProduct!.id;
                    productName = selectedProduct!.name;
                  } else {
                    final v = double.tryParse(amountCtrl.text.trim());
                    if (v == null) throw 'أدخل مبلغاً صحيحاً';
                    delta = v;
                  }
                  if (type == 'credit') delta = -delta.abs(); else delta = delta.abs();

                  await db.insertInvoiceAdjustment(
                    InvoiceAdjustment(
                      invoiceId: invoiceToManage!.id!,
                      type: type,
                      amountDelta: delta,
                      productId: productId,
                      productName: productName,
                      quantity: qty,
                      price: price,
                      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                    ),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تمت إضافة التسوية')),
                    );
                  }
                  Navigator.pop(ctx, true);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

}

class EditableInvoiceItemRow extends StatefulWidget {
  final InvoiceItem item;
  final int index;
  final Function(InvoiceItem) onItemUpdated;
  final Function(String) onItemRemovedByUid;
  final List<Product> allProducts;
  final bool isViewOnly;
  final bool isPlaceholder;
  final FocusNode? detailsFocusNode; // جديد: لقبول FocusNode لحقل التفاصيل
  final FocusNode? quantityFocusNode; // جديد: لطلب التركيز على العدد من الخارج
  final FocusNode? priceFocusNode; // جديد: لطلب التركيز على السعر من الخارج
  final DatabaseService? databaseService; // جديد: للبحث الذكي
  final String currentCustomerName; // اسم العميل الحالي لقراءة سجل أسعاره
  final String? currentCustomerPhone; // هاتف العميل لتحسين المطابقة
  final VoidCallback? onPriceSubmitted; // جديد: للانتقال إلى الصف التالي عند الضغط على Enter في السعر
  final bool allowNegativeStock; // جديد: للسماح بالبيع بالسالب أو منعه
  final List<String> Function()? getCurrentInvoiceProductNames; // المنتجات الحالية لخفض أولويتها في البحث

  const EditableInvoiceItemRow({
    Key? key,
    required this.item,
    required this.index,
    required this.onItemUpdated,
    required this.onItemRemovedByUid,
    required this.allProducts,
    required this.isViewOnly,
    required this.isPlaceholder,
    this.detailsFocusNode,
    this.quantityFocusNode,
    this.priceFocusNode,
    this.databaseService, // جديد: للبحث الذكي
    required this.currentCustomerName,
    this.currentCustomerPhone,
    this.onPriceSubmitted, // جديد: للانتقال إلى الصف التالي
    this.allowNegativeStock = false, // القيمة الافتراضية
    this.getCurrentInvoiceProductNames,
  }) : super(key: key);

  @override
  State<EditableInvoiceItemRow> createState() => _EditableInvoiceItemRowState();
}
class _EditableInvoiceItemRowState extends State<EditableInvoiceItemRow> {
  late InvoiceItem _currentItem;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late FocusNode _quantityFocusNode;
  late FocusNode _priceFocusNode;
  late FocusNode _detailsFocusNode;
  late FocusNode _saleTypeFocusNode;
  bool _openSaleTypeDropdown = false;
  bool _openPriceDropdown = false;
  final GlobalKey _saleTypeKey = GlobalKey(); // مفتاح لفتح قائمة نوع البيع برمجياً
  late TextEditingController _idController;
  Product? _rowIdSuggestion;
  Timer? _rowIdDebounce;
  List<Product> _rowIdOptions = [];
  TextEditingController? _detailsController; // reference to details field controller
  TextEditingController? _ownedDetailsController; // controller نملكه للـ RawAutocomplete
  bool _hasShownLowPriceWarning = false;
  bool _isRowLocked = false; // 🔒 قفل السطر في حالة نفاد المخزون
  double? _lowestRecentPrice; // أدنى سعر خلال آخر 3 فواتير
  String? _lowestRecentInfo; // وصف مختصر: التاريخ ونوع البيع
  
  // دالة للتحقق مما إذا كان سعر البيع أقل من سعر التكلفة
  bool _isPriceBelowCost() {
    if (_currentItem.appliedPrice <= 0) return false;
    if (_currentItem.productName.isEmpty) return false;
    
    double quantity = _currentItem.quantityIndividual ??
        _currentItem.quantityLargeUnit ?? 1;
    if (quantity <= 0) quantity = 1;
    
    double? effectiveCostPerUnit;
    
    // أولاً: جرب من actualCostPrice
    // 🔧 التحقق الدفاعي: تجاهل actualCostPrice إذا كان يساوي سعر القطعة بينما نبيع بوحدة كبيرة
    // هذا يضمن إعادة الحساب من الهرمية إذا كان التخزين الأولي خاطئاً
    bool useStoredActualCost = false;
    if (_currentItem.actualCostPrice != null && _currentItem.actualCostPrice! > 0) {
       useStoredActualCost = true;
       // إذا كان البيع بوحدة كبيرة (ليست قطعة أو متر)
       if (_currentItem.saleType != 'قطعة' && _currentItem.saleType != 'متر') {
          // جلب سعر القطعة للمقارنة
           final product = widget.allProducts.firstWhere(
            (p) => p.name == _currentItem.productName,
            orElse: () => Product(
              id: null, 
              name: '', 
              unit: '', 
              unitPrice: 0, 
              price1: 0,
              createdAt: DateTime.now(), // 🔧 Added missing parameter
              lastModifiedAt: DateTime.now(), // 🔧 Added missing parameter
            ),
          );
          // إذا كانت التكلفة المخزنة تساوي تكلفة القطعة الواحدة، فهذا يعني أن الحساب الأولي كان خاطئاً
          // لذا نتجاهله وندع الدالة تحسبه من جديد باستخدام المنطق القوي في الأسفل
          final double baseCost = product.costPrice ?? 0.0;
          if ((_currentItem.actualCostPrice! - baseCost).abs() < 0.01) {
             useStoredActualCost = false;
          }
       }
    }

    if (useStoredActualCost) {
      effectiveCostPerUnit = _currentItem.actualCostPrice;
    } 
    // ثانياً: جرب من costPrice (للقطعة الواحدة)
    else if (_currentItem.costPrice != null && _currentItem.costPrice! > 0 && quantity > 1 && (_currentItem.saleType == 'قطعة' || _currentItem.saleType == 'متر')) {
       // هذا الشرط خاص فقط إذا كنا نبيع كمية من القطع، ونريد مقارنة سعر المجموعة (وهو غير مطبق هنا لأن appliedPrice للوحدة)
       // انتظر، effectiveCostPerUnit يجب أن يكون للوحدة الواحدة (التي هي هنا "باكيت" كامل)
       // لذا الشرط السابق كان: costPrice! / quantity وهذا كان يفترض أن costPrice هو للمجموع.
       // دعنا نعتمد على المنطق القوي في الأسفل
    }
    // ثالثاً: جلب التكلفة من المنتج الأصلي (المنطق القوي)
    if (effectiveCostPerUnit == null) {
      final product = widget.allProducts.firstWhere(
        (p) => p.name == _currentItem.productName,
        orElse: () => Product(
          id: null, name: '', unit: 'piece', unitPrice: 0, price1: 0,
          createdAt: DateTime.now(), lastModifiedAt: DateTime.now(),
        ),
      );
      
      if (product.name.isNotEmpty) {
        final String saleType = _currentItem.saleType ?? 'قطعة';
        final Map<String, double> unitCosts = product.getUnitCostsMap();
        
        // جرب من unit_costs أولاً
        if (unitCosts.containsKey(saleType) && unitCosts[saleType]! > 0) {
          effectiveCostPerUnit = unitCosts[saleType];
        }
        // ثم من costPrice الأساسي للمنتج مع حساب المضاعف من الهرمية
        else if (product.costPrice != null && product.costPrice! > 0) {
          // إذا كان البيع بوحدة كبيرة، احسب التكلفة من الهرمية
          if (saleType != 'قطعة' && saleType != 'متر') {
            double multiplier = 1.0;
            
            // 🔧 Fix: استخدام unitHierarchy للحساب الصحيح مع fallback قوي
            if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
              try {
                // محاولة تحليل JSON مع دعم علامات الاقتباس المفردة والمزدوجة
                List<dynamic> hierarchy;
                try {
                  hierarchy = jsonDecode(product.unitHierarchy!); 
                } catch (_) {
                  hierarchy = jsonDecode(product.unitHierarchy!.replaceAll("'", '"'));
                }

                for (final level in hierarchy) {
                  final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                  final double qty = (level['quantity'] is num)
                      ? (level['quantity'] as num).toDouble()
                      : double.tryParse(level['quantity'].toString()) ?? 1.0;
                  multiplier *= qty;
                  if (unitName == saleType) break;
                }
              } catch (_) {
                // استخدام unitsInLargeUnit كـ fallback
                multiplier = _currentItem.unitsInLargeUnit ?? 1;
              }
            } else {
              multiplier = _currentItem.unitsInLargeUnit ?? 1;
            }
            
            effectiveCostPerUnit = product.costPrice! * multiplier;
          } else {
            effectiveCostPerUnit = product.costPrice;
          }
        }
      }
    }
    
    if (effectiveCostPerUnit == null || effectiveCostPerUnit <= 0) return false;
    
    const double eps = 1e-6;
    return (_currentItem.appliedPrice + eps) < effectiveCostPerUnit;
  }

  // 🔒 التحقق من المخزون عند الكتابة اليدوية لاسم المنتج
  void _validateStockByManualName(String name) {
    if (widget.allowNegativeStock) {
      if (_isRowLocked) setState(() => _isRowLocked = false);
      return;
    }
    
    final sanitizedInput = name.trim().replaceAll(' ', '');
    if (sanitizedInput.isEmpty) {
       if (_isRowLocked) setState(() => _isRowLocked = false);
       return;
    }

    Product? matchingProduct;
    try {
      // مقارنة الاسم بدون فواصل كما طلب المستخدم
      matchingProduct = widget.allProducts.firstWhere(
        (p) => p.name.trim().replaceAll(' ', '') == sanitizedInput,
      );
    } catch (_) {}

    final shouldLock = matchingProduct != null && (matchingProduct.stockQuantity ?? 0) <= 0;
    
    if (shouldLock != _isRowLocked) {
      setState(() {
        _isRowLocked = shouldLock;
      });
      
      if (shouldLock) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ هذا الصنف نافذ من المخزون! تم قفل السطر.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatNumber(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }
  
  // دالة للحصول على أو إنشاء TextEditingController للتفاصيل
  TextEditingController _getOrCreateDetailsController() {
    _ownedDetailsController ??= TextEditingController(text: widget.item.productName);
    return _ownedDetailsController!;
  }

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    // استخدم المتحكمات الجاهزة من كائن الصنف مباشرة
    _quantityController = TextEditingController(
      text: (widget.item.quantityIndividual ??
              widget.item.quantityLargeUnit ??
              '')
          .toString(),
    );
    _priceController = widget.item.appliedPriceController;
    _detailsFocusNode = widget.detailsFocusNode ?? FocusNode();
    _quantityFocusNode = widget.quantityFocusNode ?? FocusNode();
    _priceFocusNode = widget.priceFocusNode ?? FocusNode();
    _saleTypeFocusNode = FocusNode();
    
    // إضافة listener لنقل التركيز إلى Autocomplete عند طلب التركيز على _detailsFocusNode
    _detailsFocusNode.addListener(_onDetailsFocusChanged);
    // 🎯 إضافة listener لتظليل كامل السعر عند استقبال المؤشر
    _priceFocusNode.addListener(_onPriceFocusChanged);
    
    // Initialize ID controller from current product if resolvable
    final prod = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    _idController = TextEditingController(text: prod.id?.toString() ?? '');
    // احضر أدنى سعر تاريخي بمجرد تهيئة الصف
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLowestRecentPrice();
    });
  }
  
  // دالة للتعامل مع تغيير التركيز على حقل التفاصيل
  void _onDetailsFocusChanged() {
    // يمكن إضافة منطق هنا إذا لزم الأمر
  }

  // 🎯 دالة لتظليل كامل السعر عند استقبال التركيز
  void _onPriceFocusChanged() {
    if (_priceFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_priceFocusNode.hasFocus && _priceController.text.isNotEmpty) {
          _priceController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _priceController.text.length,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    // إزالة الـ listeners قبل التخلص من FocusNode
    _detailsFocusNode.removeListener(_onDetailsFocusChanged);
    _priceFocusNode.removeListener(_onPriceFocusChanged);
    
    // تنظيف الـ controller الذي نملكه
    _ownedDetailsController?.dispose();
    
    if (widget.detailsFocusNode == null) {
      _detailsFocusNode.dispose();
    }
    if (widget.quantityFocusNode == null) {
      _quantityFocusNode.dispose();
    }
    if (widget.priceFocusNode == null) {
      _priceFocusNode.dispose();
    }
    _saleTypeFocusNode.dispose();
    _rowIdDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(EditableInvoiceItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // مزامنة الحالة الداخلية عندما يتم تحديث العنصر من الخارج
    // هذا يحل مشكلة عدم ظهور التحديثات في واجهة المستخدم عند التعديلات المتكررة
    if (oldWidget.item.uniqueId == widget.item.uniqueId) {
      // تحقق من وجود تغييرات فعلية
      bool hasChanges = false;
      
      if (_currentItem.quantityIndividual != widget.item.quantityIndividual) hasChanges = true;
      if (_currentItem.quantityLargeUnit != widget.item.quantityLargeUnit) hasChanges = true;
      if (_currentItem.appliedPrice != widget.item.appliedPrice) hasChanges = true;
      if (_currentItem.saleType != widget.item.saleType) hasChanges = true;
      if (_currentItem.itemTotal != widget.item.itemTotal) hasChanges = true;
      if (_currentItem.productName != widget.item.productName) hasChanges = true;
      
      if (hasChanges) {
        // تحديث البيانات فوراً داخلياً
        _currentItem = widget.item;
        
        // استخدام post-frame callback لتجنب خطأ markNeedsBuild during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            // تحديث الـ controllers لتعكس القيم الجديدة
            final quantity = (widget.item.quantityIndividual ?? 
                widget.item.quantityLargeUnit ?? '').toString();
            if (_quantityController.text != quantity) {
              _quantityController.text = quantity;
            }
            
            final priceText = _formatNumber(widget.item.appliedPrice);
            if (_priceController.text != priceText) {
              _priceController.text = priceText;
            }
            
            // تحديث controller التفاصيل إذا كان موجوداً
            if (_detailsController != null && _detailsController!.text != widget.item.productName) {
              _detailsController!.text = widget.item.productName;
            }
          });
        });
      }
    }
  }

  List<DropdownMenuItem<String>> _getUnitOptions() {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );

    // 🧠 Use the centralized method to get all units (base + hierarchy)
    List<String> options = product.getAllUnitLevels();

    // Fallback if empty (should not happen for valid products)
    if (options.isEmpty) {
      if (product.unit == 'piece') {
        options = ['قطعة'];
      } else if (product.unit == 'meter') {
        options = ['متر'];
        if (product.lengthPerUnit != null) options.add('لفة');
      } else {
        options = [product.unit];
      }
    }

    // Ensure valid entries only
    options = options.where((e) => e.isNotEmpty).toSet().toList();

    // Ensure currently selected value is present
    if (_currentItem.saleType != null &&
        _currentItem.saleType!.isNotEmpty &&
        !options.contains(_currentItem.saleType)) {
      options.add(_currentItem.saleType!);
    }

    return options
        .map((unit) => DropdownMenuItem(
              value: unit,
              child: Text(unit, textAlign: TextAlign.center),
            ))
        .toList();
  }


  // دالة لفتح قائمة نوع البيع برمجياً مع دعم التنقل بالكيبورد
  // 🔧 تحسين: فتح القائمة مع التركيز على أول خيار، Enter يختار ذلك الخيار
  Future<void> _showSaleTypeMenu() async {
    final RenderBox? renderBox =
        _saleTypeKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    // الحصول على خيارات نوع البيع
    final options = _getUnitOptionsStrings();
    if (options.isEmpty) return;

    // إذا كان هناك خيار واحد فقط، اختره مباشرة وانتقل للسعر
    if (options.length == 1) {
      _updateSaleType(options.first);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _priceFocusNode.requestFocus();
      });
      return;
    }

    // تعيين أول خيار كقيمة افتراضية قبل فتح القائمة
    if (_currentItem.saleType == null || _currentItem.saleType!.isEmpty) {
      _updateSaleType(options.first);
    }

    // فتح القائمة المنبثقة المخصصة مع دعم التنقل بالكيبورد
    final String? selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext dialogContext) {
        return _SaleTypeDropdownDialog(
          options: options,
          initialValue: _currentItem.saleType ?? options.first,
          position: offset,
          size: size,
        );
      },
    );

    if (selected != null) {
      _updateSaleType(selected);
    }
    
    // الانتقال إلى حقل السعر بعد الاختيار أو الإغلاق
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _priceFocusNode.requestFocus();
    });
  }
  
  // دالة مساعدة للحصول على خيارات نوع البيع كـ List<String>
  List<String> _getUnitOptionsStrings() {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    
    // 🔧 استخدام method موجود في Product model لجلب جميع الوحدات
    List<String> options = product.getAllUnitLevels();
    
    // إذا كانت القائمة فارغة، استخدم الوحدة الأساسية
    if (options.isEmpty) {
      final baseUnit = product.unit == 'piece' ? 'قطعة' : (product.unit == 'meter' ? 'متر' : product.unit);
      options = [baseUnit];
    }
    
    // تنظيف القائمة
    options = options.where((e) => e.isNotEmpty).toSet().toList();
    
    // إضافة نوع البيع الحالي إذا لم يكن موجوداً
    if (_currentItem.saleType != null &&
        _currentItem.saleType!.isNotEmpty &&
        !options.contains(_currentItem.saleType)) {
      options.add(_currentItem.saleType!);
    }
    return options;
  }

  void _updateQuantity(String value) {
    double? newQuantity = safeParseDouble(value);
    if (newQuantity == null || newQuantity <= 0) return;

    // 🔒 التحقق من المخزون
    if (!widget.allowNegativeStock) {
      // جلب المنتج للتأكد من الرصيد الحالي
      final product = widget.allProducts.firstWhere(
        (p) => p.name == _currentItem.productName,
        orElse: () => Product(id: null, name: '', unit: 'piece', unitPrice: 0, price1: 0, 
            createdAt: DateTime.now(), lastModifiedAt: DateTime.now()),
      );
      
      if (product.id != null) {
        // حساب الكمية بالوحدة الأساسية
        double conversionFactor = 1.0;
        if (product.unit == 'piece' && _currentItem.saleType != 'قطعة') {
           try {
             List<dynamic> hierarchy = json.decode(product.unitHierarchy!.replaceAll("'", '"'));
             for (var unit in hierarchy) {
               if ((unit['unit_name'] ?? unit['name']) == _currentItem.saleType) {
                 conversionFactor = (unit['quantity'] as num).toDouble();
                 break;
               }
             }
           } catch (_) {}
        } else if (product.unit == 'meter' && _currentItem.saleType == 'لفة') {
           conversionFactor = product.lengthPerUnit ?? 1.0;
        }
        
        final double totalBaseUnits = newQuantity * conversionFactor;
        if ((product.stockQuantity ?? 0) < totalBaseUnits) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ الرصيد غير كافٍ! المتاح: ${product.stockQuantity ?? 0}'),
              backgroundColor: Colors.red,
            ),
          );
          // 🔒 BLOCK the update
          return; 
        }
      }
    }

    setState(() {
      // منطق موحد: دائماً المبلغ = السعر الحالي × العدد الحالي مباشرة
      _currentItem = _currentItem.copyWith(
        quantityIndividual:
            (_currentItem.saleType == 'قطعة' || _currentItem.saleType == 'متر')
                ? newQuantity
                : null,
        quantityLargeUnit:
            (_currentItem.saleType != 'قطعة' && _currentItem.saleType != 'متر')
                ? newQuantity
                : null,
        itemTotal: newQuantity * _currentItem.appliedPrice,
      );
      // لا تفرض ".00" عند الكتابة؛ استخدم تنسيق أرقام بدون كسور ثابتة
      _priceController.text = _formatNumber(_currentItem.appliedPrice);
    });
    widget.onItemUpdated(_currentItem);
  }

  Future<void> _updateSaleType(String newType) async {
    print('🔍 [تشخيص-صف-تغيير-وحدة] "${_currentItem.productName}" → "$newType" '
        '(السابقة: ${_currentItem.saleType} | السعر الحالي: ${_currentItem.appliedPrice})');
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    double conversionFactor = 1.0;
    if (product != null) {
      print('🔍 [تشخيص-صف] unit="${product.unit}" | unitHierarchy=${product.unitHierarchy} | isWeighable=${product.isWeighable}');
      if (product.unit == 'piece' && newType != 'قطعة') {
        if (product.unitHierarchy != null &&
            product.unitHierarchy!.isNotEmpty) {
          try {
            List<dynamic> hierarchy =
                json.decode(product.unitHierarchy!.replaceAll("'", '"'));
            for (var unit in hierarchy) {
              if ((unit['unit_name'] ?? unit['name']) == newType) {
                conversionFactor = (unit['quantity'] as num).toDouble();
                break;
              }
            }
          } catch (e) {}
        }
      } else if (product.unit == 'meter' && newType == 'لفة') {
        conversionFactor = product.lengthPerUnit ?? 1.0;
      } else if (newType != 'قطعة') {
        print('    ⚠️ [تشخيص-صف] لا فرع تحويل: unit="${product.unit}" ليست piece/mتر → معامل=1 (سبب خطأ الموزونات)');
      }
    }
    print('    معامل التحويل المحسوب: $conversionFactor');

    // 🧠 استشارة محرك التسعير الذكي لنوع البيع المحدد
    double newAppliedPrice = 0.0;
    bool smartPriceFound = false;
    if (product != null && product.id != null) {
      try {
        final db = widget.databaseService ?? DatabaseService();
        int? custId;
        final custName = widget.currentCustomerName.trim();
        if (custName.isNotEmpty) {
          final c = await db.findCustomerByNormalizedName(custName);
          if (c != null) custId = c.id;
        }
        final smartResult = await SmartPricingService().getSmartPriceEnhanced(
          productId: product.id!,
          customerId: custId,
          saleType: newType,
        );
        if (smartResult != null && smartResult.price > 0) {
          newAppliedPrice = smartResult.price;
          smartPriceFound = true;
          final double baseForCalc = _currentItem.appliedPrice > 0
              ? _currentItem.appliedPrice
              : (product?.unitPrice ?? 0.0);
          print('    🧠 [تشخيص-صف] التسعير الذكي طغى على التحويل! سعره=${smartResult.price} '
              '(التحويل الحسابي كان سيعطي: ${baseForCalc * conversionFactor})');
        }
      } catch (_) {}
    }

    if (!smartPriceFound) {
      if ((product?.unit == 'piece' && newType != 'قطعة') ||
          (product?.unit == 'meter' && newType == 'لفة')) {
        // عند التحويل من قطعة إلى باكيت أو من متر إلى لفة: السعر للوحدة الكبيرة = السعر الحالي × عامل التحويل
        newAppliedPrice = (_currentItem.appliedPrice > 0 ? _currentItem.appliedPrice : (product?.unitPrice ?? 0.0)) * conversionFactor;
      } else if ((product?.unit == 'piece' &&
              _currentItem.saleType != 'قطعة' &&
              newType == 'قطعة') ||
          (product?.unit == 'meter' &&
              _currentItem.saleType == 'لفة' &&
              newType == 'متر')) {
        // عند التحويل من باكيت إلى قطعة أو من لفة إلى متر: السعر للوحدة الصغيرة = السعر الحالي ÷ عامل التحويل
        newAppliedPrice = _currentItem.appliedPrice / conversionFactor;
      } else {
        newAppliedPrice = _currentItem.appliedPrice > 0 ? _currentItem.appliedPrice : (product?.unitPrice ?? 0.0);
      }
    }

    double quantity = _currentItem.quantityIndividual ??
        _currentItem.quantityLargeUnit ??
        1;
    setState(() {
      _currentItem = _currentItem.copyWith(
        saleType: newType,
        appliedPrice: newAppliedPrice,
        unitsInLargeUnit: conversionFactor != 1.0 ? conversionFactor : null,
        itemTotal: quantity * newAppliedPrice,
        quantityIndividual:
            (newType == 'قطعة' || newType == 'متر') ? quantity : null,
        quantityLargeUnit:
            (newType != 'قطعة' && newType != 'متر') ? quantity : null,
      );
      print('    ✅ [تشخيص-صف] السعر الجديد: $newAppliedPrice | المجموع: ${quantity * newAppliedPrice} | smartPriceUsed=$smartPriceFound');
      _quantityController.text = quantity.toString();
      // لا تفرض ".00" أثناء التحرير؛ اظهر فواصل فقط
      _priceController.text =
          (newAppliedPrice > 0) ? _formatNumber(newAppliedPrice) : '';
      widget.onItemUpdated(_currentItem);
      // بعد اختيار نوع البيع، انتقل تلقائياً إلى السعر
      FocusScope.of(context).requestFocus(_priceFocusNode);
    });

    // 🎯 تظليل السعر بالكامل فوراً عند الانتقال
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_priceFocusNode.hasFocus && _priceController.text.isNotEmpty) {
        _priceController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _priceController.text.length,
        );
      }
    });

    // تحديث أقل سعر تاريخي عند تغيير نوع البيع
    _fetchLowestRecentPrice();
  }

  void _updatePrice(String value) {
    if (value.trim().isEmpty) {
      setState(() {
        double quantity = _currentItem.quantityIndividual ??
            _currentItem.quantityLargeUnit ??
            1;
        _currentItem = _currentItem.copyWith(
          appliedPrice: 0.0,
          itemTotal: 0.0,
        );
      });
      widget.onItemUpdated(_currentItem);
      _fetchLowestRecentPrice();
      return;
    }
    double? newPrice = safeParseDouble(value);
    if (newPrice == null || newPrice < 0) return;
    setState(() {
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      // منطق السعر المخصص: إذا كان المستخدم أدخل سعراً يدوياً (غير مطابق لسعر الوحدة أو سعر التكلفة)
      bool isCustomPrice = true;
      
      // 🔧 Fix: استخدم _isPriceBelowCost للتحقق الموحد من التكلفة
      // هذا يشمل حساب التكلفة من الهرمية للوحدات الكبيرة
      // أولاً: حدّث appliedPrice مؤقتاً للتحقق
      _currentItem = _currentItem.copyWith(appliedPrice: newPrice);
      
      if (_isPriceBelowCost()) {
        if (!_hasShownLowPriceWarning) {
          _hasShownLowPriceWarning = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ السعر المدخل أقل من سعر التكلفة!'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          });
          // إعادة تعيين السماح بعرض التحذير مرة أخرى بعد التعديل التالي إذا لزم
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) setState(() => _hasShownLowPriceWarning = false);
          });
        }
      }
      // الحساب: المبلغ = السعر * العدد مباشرة بغض النظر عن نوع الوحدة
      _currentItem = _currentItem.copyWith(
        appliedPrice: newPrice,
        itemTotal: quantity * newPrice,
      );
      // اترك المُدخل كما يكتبه المستخدم؛ المُنسق سيضيف الفواصل تلقائياً
    });
    widget.onItemUpdated(_currentItem);
    // تحديث الأيقونة حسب السعر الحالي
    _fetchLowestRecentPrice();
  }

  Future<void> _fetchLowestRecentPrice() async {
    try {
      final db = widget.databaseService;
      if (db == null) return;
      final String customer = widget.currentCustomerName.trim();
      if (customer.isEmpty) return;
      final String productName = _currentItem.productName.trim();
      if (productName.isEmpty) return;
      final results = await db.getLastNPricesForCustomerProduct(
        customerName: customer,
        customerPhone: widget.currentCustomerPhone,
        productName: productName,
        limit: 3,
        saleType: _currentItem.saleType,
      );
      if (results.isEmpty) {
        setState(() {
          _lowestRecentPrice = null;
          _lowestRecentInfo = null;
        });
        return;
      }
      double minPrice = results
          .map((r) => (r['applied_price'] as num).toDouble())
          .reduce((a, b) => a < b ? a : b);
      final minRow = results.firstWhere(
          (r) => (r['applied_price'] as num).toDouble() == minPrice,
          orElse: () => results.first);
      final String dateStr = (minRow['invoice_date'] as String?) ?? '';
      final int? invoiceId = (minRow['invoice_id'] as int?);
      final String saleType = (minRow['sale_type'] as String?) ?? (_currentItem.saleType ?? '');
      setState(() {
        _lowestRecentPrice = minPrice;
        final String d = dateStr.isNotEmpty ? dateStr : '';
        final String idText = invoiceId != null ? 'فاتورة #${minRow['invoice_number'] ?? invoiceId}' : '';
        _lowestRecentInfo = [idText, d, saleType].where((s) => s != null && s.toString().trim().isNotEmpty).join(' — ');
      });
    } catch (_) {
      // ignore أخطاء الاستعلام البسيطة
    }
  }

  Future<void> _applyProductSelection(Product prod) async {
    final saleType = (prod.unit == 'piece') ? 'قطعة' : ((prod.unit == 'meter') ? 'متر' : prod.unit);
    
    // 🧠 حساب السعر الذكي للمنتج بناءً على العميل ونوع البيع
    double suggestedPrice = prod.unitPrice > 0 ? prod.unitPrice : prod.price1;
    try {
      final db = widget.databaseService ?? DatabaseService();
      int? custId;
      final custName = widget.currentCustomerName.trim();
      if (custName.isNotEmpty) {
        final c = await db.findCustomerByNormalizedName(custName);
        if (c != null) custId = c.id;
      }
      if (prod.id != null) {
        final smartResult = await SmartPricingService().getSmartPriceEnhanced(
          productId: prod.id!,
          customerId: custId,
          saleType: saleType,
        );
        if (smartResult != null && smartResult.price > 0) {
          suggestedPrice = smartResult.price;
        }
      }
    } catch (_) {}

    final quantity = _currentItem.quantityIndividual ?? _currentItem.quantityLargeUnit ?? 1.0;

    setState(() {
      _idController.text = prod.id?.toString() ?? '';
      _rowIdSuggestion = null;
      _currentItem = _currentItem.copyWith(
        productId: prod.id, // ✅ Critical: Update ID
        productName: prod.name,
        unit: prod.unit,
        unitPrice: prod.unitPrice,
        saleType: saleType,
        appliedPrice: suggestedPrice,
        itemTotal: quantity * suggestedPrice,
        quantityIndividual: (saleType == 'قطعة' || saleType == 'متر') ? quantity : null,
        quantityLargeUnit: (saleType != 'قطعة' && saleType != 'متر') ? quantity : null,
      );
      // مزامنة خانة التفاصيل والسعر فوراً
      _detailsController?.text = prod.name;
      _priceController.text = suggestedPrice > 0 ? _formatNumber(suggestedPrice) : '';
    });
    widget.onItemUpdated(_currentItem);
    // نقل المؤشر مباشرة إلى حقل العدد
    FocusScope.of(context).requestFocus(_quantityFocusNode);
    // بعد اختيار المنتج، حدّث أقل سعر تاريخي لعرض الأيقونة إن لزم
    _fetchLowestRecentPrice();
  }

  String formatCurrency(num value) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return formatter.format(value);
  }
  @override
  Widget build(BuildContext context) {
    // لون الخطوط الفاصلة بين الأعمدة - أغمق للوضوح
    final Color gridBorderColor = Colors.grey.shade500;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: gridBorderColor, width: 1),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // رقم الصف
            Expanded(
              flex: 1,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                child: Text((widget.index + 1).toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),

            // التفاصيل (اسم المنتج) - Increased Flex (5 -> 7)
            Expanded(
              flex: 7, 
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(widget.item.productName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium)
                    : RawAutocomplete<Product>(
                        displayStringForOption: (Product p) => p.name,
                        textEditingController: _getOrCreateDetailsController(),
                        focusNode: _detailsFocusNode, // استخدام FocusNode الممرر من الخارج مباشرة
                        optionsBuilder: (TextEditingValue textEditingValue) async {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Product>.empty();
                          }
                          try {
                            // 🧠 استخدام البحث الذكي مع تمرير قائمة المنتجات الحالية لخفض أولويتها
                            final currentNames = widget.getCurrentInvoiceProductNames?.call();
                            return await SmartSearchService.instance.smartSearch(
                              textEditingValue.text,
                              currentInvoiceProductNames: currentNames,
                            );
                          } catch (e) {
                            print('Error in smart search: $e');
                            return widget.allProducts
                                .where((p) => p.name.contains(textEditingValue.text));
                          }
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          _detailsController = controller;
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            enabled: !widget.isViewOnly,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF5F5F5),
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                            onChanged: (val) {
                              _currentItem = _currentItem.copyWith(productName: val);
                              _validateStockByManualName(val); // 🔍 تحقق عند كل تغييرة
                            },
                            onSubmitted: (val) {
                              onFieldSubmitted();
                              _validateStockByManualName(val); // 🔍 تحقق نهائي عند الضغط على Enter
                              final sanitizedInput = val.trim().replaceAll(' ', '');
                              if (sanitizedInput.isNotEmpty) {
                                try {
                                  final matchingProduct = widget.allProducts.firstWhere(
                                    (p) => p.name.trim().replaceAll(' ', '') == sanitizedInput,
                                  );
                                  _applyProductSelection(matchingProduct);
                                } catch (_) {}
                              }
                              widget.onItemUpdated(_currentItem);
                              if (!_isRowLocked) {
                                FocusScope.of(context).requestFocus(_quantityFocusNode);
                              }
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4.0,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 250, maxWidth: 350),
                                child: _ProductAutoScrollListView(
                                  options: options.toList(),
                                  onSelected: onSelected,
                                ),
                              ),
                            ),
                          );
                        },
                        onSelected: (Product selection) {
                           // 🔒 التحقق من المخزون عند الاختيار من الجدول
                           if (!widget.allowNegativeStock && (selection.stockQuantity ?? 0) <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('⚠️ هذا الصنف نافذ من المخزون! لا يمكن اختياره.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              // تصفير الحقل أو إعادته للاسم القديم
                              _detailsController?.text = _currentItem.productName;
                              return;
                           }

                           _applyProductSelection(selection);
                           if (_isRowLocked) setState(() => _isRowLocked = false); // إعادة التعيين عند الاختيار الصحيح
                           SmartSearchService.instance.addProductToSession(selection.id, selection.name);
                           FocusScope.of(context).requestFocus(_quantityFocusNode);
                        },
                      ),
              ),
            ),
            // العدد
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                alignment: Alignment.center,
                child: widget.isViewOnly
                    ? Text(
                        ((widget.item.quantityIndividual ??
                                    widget.item.quantityLargeUnit) ??
                                '')
                            .toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : TextFormField(
                        controller: _quantityController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        enabled: !widget.isViewOnly && !_isRowLocked, // 🔒 قفل الحقل
                        onChanged: _updateQuantity, // الآن أصبح آمناً
                        focusNode: _quantityFocusNode,
                        onFieldSubmitted: (val) {
                          widget.onItemUpdated(_currentItem);
                          // فتح قائمة نوع البيع مباشرة بضغطة Enter واحدة
                          _showSaleTypeMenu();
                        },
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                        ),
                      ),
              ),
            ),
            // نوع البيع
            Expanded(
              flex: 2,
              child: Container(
                key: _saleTypeKey, // مفتاح لتحديد موقع القائمة المنبثقة
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400, width: 1),
                          borderRadius: BorderRadius.circular(4),
                          color: const Color(0xFFF5F5F5),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        child: Text(
                          widget.item.saleType ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400, width: 1),
                          borderRadius: BorderRadius.circular(4),
                          color: const Color(0xFFF5F5F5),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _currentItem.saleType,
                            items: _getUnitOptions(),
                            onChanged: (widget.isViewOnly || _isRowLocked)
                                ? null
                                : (value) => _updateSaleType(value!),
                            isExpanded: true,
                            alignment: AlignmentDirectional.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                            itemHeight: 48,
                            autofocus: _openSaleTypeDropdown,
                            focusNode: _saleTypeFocusNode,
                            onTap: () {
                              setState(() {
                                _openSaleTypeDropdown = false;
                              });
                            },
                          ),
                        ),
                      ),
              ),
            ),
            // السعر
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(
                        formatCurrency(widget.item.appliedPrice),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : TextFormField(
                        controller: _priceController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        enabled: !widget.isViewOnly && !_isRowLocked, // 🔒 قفل الحقل
                        inputFormatters: [
                          ThousandSeparatorDecimalInputFormatter(),
                        ],
                        onChanged: _updatePrice, // الآن أصبح آمناً
                        focusNode: _priceFocusNode,
                        onFieldSubmitted: (val) {
                          widget.onItemUpdated(_currentItem);
                          // عند الضغط على Enter في حقل السعر، انتقل إلى حقل التفاصيل في الصف التالي
                          if (widget.onPriceSubmitted != null && !_isRowLocked) {
                            widget.onPriceSubmitted!();
                          }
                        },
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          // 🔧 إضافة مؤشر بصري للبيع بخسارة
                          // 🔧 تم إزالة أيقونة التحذير من داخل الحقل بناءً على طلب المستخدم
                          // والاكتفاء بالأيقونة الموجودة بجانب زر الحذف
                          suffixIcon: null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                        ),
                      ),
              ),
            ),
            if (!widget.isViewOnly)
            Expanded(
              flex: 2,
              child: Container(
                alignment: Alignment.center,
                child: widget.isViewOnly
                  ? ((widget.item.saleType == 'قطعة' ||
                          widget.item.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          widget.item.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium))
                  : (_currentItem.saleType == 'قطعة' ||
                          _currentItem.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          _currentItem.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
            // المبلغ (Total) - Moved to end
            Expanded(
              flex: 2,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                child: widget.isViewOnly
                    ? Text(
                        formatCurrency(widget.item.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      )
                    : Text(
                        formatCurrency(_currentItem.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      ),
              ),
            ),
            // أيقونات التنبيه في أقصى اليمين
            SizedBox(
              width: 80, // زيادة العرض لاستيعاب أيقونتين
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // أيقونة تحذير حمراء: سعر البيع أقل من التكلفة
                  Builder(builder: (context) {
                    final bool showCostWarning = !widget.isViewOnly && 
                        !widget.isPlaceholder &&
                        _isPriceBelowCost();
                    if (!showCostWarning) return const SizedBox.shrink();
                    return Tooltip(
                      message: '⚠️ تحذير: سعر البيع أقل من سعر التكلفة!',
                      preferBelow: false,
                      child: const Icon(Icons.warning,
                          color: Colors.red, size: 22),
                    );
                  }),
                  // أيقونة تنبيه برتقالية: سعر أعلى من سعر سابق
                  Builder(builder: (context) {
                    final bool showIcon = _lowestRecentPrice != null &&
                        !widget.isViewOnly &&
                        _currentItem.appliedPrice > (_lowestRecentPrice ?? 0);
                    if (!showIcon) return const SizedBox.shrink();
                    return Tooltip(
                      message:
                          'سعر أقل سابقاً: ${formatCurrency(_lowestRecentPrice!)}\n${_lowestRecentInfo ?? ''}',
                      preferBelow: false,
                      child: Icon(Icons.error_outline,
                          color: Colors.orange.shade700, size: 22),
                    );
                  }),
                ],
              ),
            ),
            if (!widget.isViewOnly && !widget.isPlaceholder)
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 24),
                  onPressed: () =>
                      widget.onItemRemovedByUid(widget.item.uniqueId),
                  tooltip: 'حذف الصنف',
                ),
              )
            else
              const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

// أضف دالة مساعدة للتحقق من اكتمال الصف
bool _isInvoiceItemComplete(InvoiceItem item) {
  // التحقق من أن الكمية موجودة وأكبر من صفر
  final hasValidQuantity = (item.quantityIndividual != null && item.quantityIndividual! > 0) ||
                           (item.quantityLargeUnit != null && item.quantityLargeUnit! > 0);
  return (item.productName.isNotEmpty &&
      hasValidQuantity &&
      item.appliedPrice > 0 &&
      item.itemTotal > 0 &&
      (item.saleType != null && item.saleType!.isNotEmpty));
}

// إدارة FocusNode لكل صف
class LineItemFocusNodes {
  FocusNode details = FocusNode();
  FocusNode quantity = FocusNode();
  FocusNode price = FocusNode();
  void dispose() {
    details.dispose();
    quantity.dispose();
    price.dispose();
  }
}

// Widget مساعد للتمرير التلقائي في قائمة الاقتراحات - للمنتجات
class _ProductAutoScrollListView extends StatefulWidget {
  final List<Product> options;
  final void Function(Product) onSelected;

  const _ProductAutoScrollListView({
    required this.options,
    required this.onSelected,
  });

  @override
  State<_ProductAutoScrollListView> createState() => _ProductAutoScrollListViewState();
}

class _ProductAutoScrollListViewState extends State<_ProductAutoScrollListView> {
  final ScrollController _scrollController = ScrollController();
  // السعر + المخزون يحتاج مساحة أكبر قليلاً
  static const double _itemHeight = 60.0; 

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHighlighted(int highlightedIndex) {
    if (!_scrollController.hasClients) return;
    
    final double targetOffset = highlightedIndex * _itemHeight;
    final double viewportHeight = _scrollController.position.viewportDimension;
    final double currentOffset = _scrollController.offset;
    
    if (targetOffset < currentOffset) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (targetOffset + _itemHeight > currentOffset + viewportHeight) {
      _scrollController.animateTo(
        targetOffset + _itemHeight - viewportHeight,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemCount: widget.options.length,
      itemExtent: _itemHeight,
      itemBuilder: (context, index) {
        final product = widget.options[index];
        final int highlightedIndex = AutocompleteHighlightedOption.of(context);
        final bool isHighlighted = highlightedIndex == index;
        
        if (isHighlighted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToHighlighted(highlightedIndex);
          });
        }
        
        return Container(
          decoration: BoxDecoration(
            // 🔧 اللون انتقل إلى tileColor — DecoratedBox الملون فوق ListTile
            // كان يخفي رشّ الحبر (assertion)
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: ListTile(
            dense: true,
            tileColor: isHighlighted ? Colors.blue.shade50 : null,
            visualDensity: VisualDensity.compact,
            title: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isHighlighted ? Colors.blue.shade900 : Colors.black87,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            subtitle: Row(
              children: [
                Text(
                  'المخزون: ${product.stockQuantity}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if ((product.stockQuantity ?? 0) <= 0) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.info_outline, color: Colors.red, size: 12),
                  const SizedBox(width: 2),
                  const Text('نفذت الكمية', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            trailing: Text(
              '${NumberFormatter.format(product.price1)} ',
              style: TextStyle(
                fontSize: 12, 
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700
              ),
            ),
            onTap: () => widget.onSelected(product),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🔧 Widget مخصص لقائمة نوع البيع مع دعم التنقل بالكيبورد
// ═══════════════════════════════════════════════════════════════════════════
class _SaleTypeDropdownDialog extends StatefulWidget {
  final List<String> options;
  final String initialValue;
  final Offset position;
  final Size size;

  const _SaleTypeDropdownDialog({
    required this.options,
    required this.initialValue,
    required this.position,
    required this.size,
  });

  @override
  State<_SaleTypeDropdownDialog> createState() => _SaleTypeDropdownDialogState();
}

class _SaleTypeDropdownDialogState extends State<_SaleTypeDropdownDialog> {
  late int _selectedIndex;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    // البدء من أول خيار (أصغر وحدة)
    _selectedIndex = 0;
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _selectAndClose() {
    Navigator.of(context).pop(widget.options[_selectedIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // خلفية شفافة للإغلاق عند النقر خارج القائمة
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(null),
            child: Container(color: Colors.transparent),
          ),
        ),
        // القائمة المنسدلة
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy + widget.size.height,
          width: widget.size.width,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(4),
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey.keyLabel == 'Arrow Down') {
                  setState(() {
                    _selectedIndex = (_selectedIndex + 1) % widget.options.length;
                  });
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Arrow Up') {
                  setState(() {
                    _selectedIndex = (_selectedIndex - 1 + widget.options.length) % widget.options.length;
                  });
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Enter') {
                  _selectAndClose();
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Escape') {
                  Navigator.of(context).pop(null);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: widget.options.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedIndex;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                        _selectAndClose();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.red.shade50 : Colors.white,
                          border: isSelected
                              ? Border.all(color: Colors.red, width: 2)
                              : null,
                        ),
                        child: Text(
                          widget.options[index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? Colors.red : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Helper for parsing doubles with Arabic numerals support
double? safeParseDouble(String value) {
  if (value.trim().isEmpty) return null;
  String normalized = value
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9')
      .replaceAll(',', ''); // Remove thousands separator
  try {
     return double.tryParse(normalized);
  } catch (e) {
     return null;
  }
}