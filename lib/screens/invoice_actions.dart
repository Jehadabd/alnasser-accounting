// lib/screens/invoice_actions.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as pp;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_settings.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/invoice_adjustment.dart';
import '../models/invoice_item.dart';
import '../models/printer_device.dart';
import '../models/product.dart';
import '../models/invoice_input_data.dart'; // ✅ Added import
import '../services/database_service.dart';
// import '../services/drive_service.dart'; // Removed
import 'package:uuid/uuid.dart';
import '../services/pdf_header.dart';
import '../services/pdf_service.dart';
import '../services/invoice_pdf_service.dart'; // لدوال PDF الفاتورة
import '../services/printing_service.dart';
import '../services/settings_manager.dart';
import '../services/smart_search/smart_search.dart'; // 🧠 البحث الذكي
import '../services/auth_service.dart'; // 👤 User authentication
import '../services/logo_service.dart'; // 🖼️ Custom logo loading
import 'create_invoice_screen.dart';
import '../controllers/invoice_controller.dart';
import '../services/firebase_sync/invoice_sync_service.dart'; // ⚡ رفع فوري بعد الحفظ
import '../services/firebase_sync/firebase_sync_helper.dart';

/// واجهة تحدد المتغيرات المطلوبة للتعامل مع الفواتير
abstract class InvoiceActionsInterface {
  bool get isSaving;
  set isSaving(bool value);
  
  GlobalKey<FormState> get formKey;
  
  Invoice? get invoiceToManage;
  set invoiceToManage(Invoice? value);
  
  TextEditingController get customerNameController;
  TextEditingController get customerPhoneController;
  TextEditingController get customerAddressController;
  TextEditingController get installerNameController;
  TextEditingController get paidAmountController;
  TextEditingController get loadingFeeController;
  

  
  List<InvoiceItem> get invoiceItems;
  
  double get discount;
  set discount(double value);
  
  String get paymentType;
  set paymentType(String value);
  
  DateTime get selectedDate;
  set selectedDate(DateTime value);
  
  DatabaseService get db;
  
  bool get isViewOnly;
  set isViewOnly(bool value);
  
  bool get savedOrSuspended;
  set savedOrSuspended(bool value);
  
  bool get hasUnsavedChanges;
  set hasUnsavedChanges(bool value);
  
  PrinterDevice? get selectedPrinter;
  set selectedPrinter(PrinterDevice? value);
  
  PrintingService get printingService;
  
  FlutterSecureStorage get storage;
}

/// Mixin للتعامل مع عمليات الفواتير
mixin InvoiceActionsMixin on State<CreateInvoiceScreen> implements InvoiceActionsInterface {
// الدوال المساعدة التي تم نقلها
  String formatNumber(num value, {bool forceDecimal = false}) {
    final formatter = NumberFormat('#,##0.##', 'en_US');
    return formatter.format(value);
  }

  String _normalizePhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    }
    if (cleaned.startsWith('0')) {
      cleaned = '964' + cleaned.substring(1);
    }
    if (!cleaned.startsWith('964')) {
      cleaned = '964' + cleaned;
    }
    return cleaned;
  }

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
  
  // Methods moved to InvoiceController

  Future<String> saveInvoicePdf(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
    try {
      final safeCustomerName =
          customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '');
      final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
      final fileName = '${safeCustomerName}_$formattedDate.pdf';

      final String? userProfile = Platform.environment['USERPROFILE'];
      if (userProfile == null) {
        throw Exception('Could not find user profile directory.');
      }
      final directory = Directory(p.join(userProfile, 'Documents', 'invoices'));

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final filePath = p.join(directory.path, fileName);
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

  Future<String> saveInvoicePdfToTemp(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
    final safeCustomerName =
        customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '');
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

  pw.Widget _headerCell(String text, pw.Font font, {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: color ?? PdfColors.black),
          textAlign: pw.TextAlign.center),
    );
  }

  pw.Widget _dataCell(String text, pw.Font font,
      {pw.TextAlign align = pw.TextAlign.center, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: color ?? PdfColors.black),
          textAlign: align),
    );
  }

  pw.Widget _summaryRow(String label, num value, pw.Font font,
      {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label,
              style: pw.TextStyle(font: font, fontSize: 11, color: color)),
          pw.SizedBox(width: 5),
          pw.Text(formatNumber(value, forceDecimal: true),
              style: pw.TextStyle(
                  font: font,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  /// دالة مساعدة لبناء صف معلومات الفاتورة
  pw.Widget _buildInvoiceInfoRow({
    required pw.Font font,
    required String customerName,
    required String customerAddress,
    required String customerPhone,
    required String invoiceDisplayNumber,
    required DateTime selectedDate,
    DateTime? createdAt,
  }) {
    // دالة تقليص النصوص
    String truncate(String text, int maxLen) {
      if (text.length <= maxLen) return text;
      return text.substring(0, maxLen - 2) + '..';
    }
    
    final dateTime = createdAt ?? DateTime.now();
    final formattedDateTime = '${selectedDate.day.toString().padLeft(2, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    
    return pw.Row(
      children: [
        // السيد (25 حرف)
        pw.Container(
          width: 130, // تمت زيادة المساحة قليلاً ليستوعب أسماء أطول
          child: pw.Text('السيد: ${truncate(customerName, 25)}',
              style: pw.TextStyle(font: font, fontSize: 11)),
        ),
        // العنوان (15 حرف)
        pw.Container(
          width: 105,
          child: pw.Text('العنوان: ${truncate(customerAddress.isNotEmpty ? customerAddress : '______', 13)}',
              style: pw.TextStyle(font: font, fontSize: 10)),
        ),
        // الهاتف (11 رقم)
        pw.Container(
          width: 95,
          child: pw.Text('الهاتف: ${customerPhone.isNotEmpty ? truncate(customerPhone, 11) : '___'}',
              style: pw.TextStyle(font: font, fontSize: 10)),
        ),
        // رقم الفاتورة
        pw.Expanded(
          child: pw.Text('رقم الفاتورة: $invoiceDisplayNumber',
              style: pw.TextStyle(font: font, fontSize: 10)),
        ),
        // التاريخ والوقت مدمجين - محاذاة لليمين (طرف الورقة)
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                formattedDateTime,
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
              pw.SizedBox(width: 4),
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Text(
                  'التاريخ:',
                  style: pw.TextStyle(font: font, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// بناء جدول الفاتورة الديناميكي بناءً على إعدادات الأعمدة
  pw.Widget _buildDynamicTableForPdf({
    required List<Map<String, dynamic>> pageRows,
    required int pageIndex,
    required int itemsPerPage,
    required List<Product> allProducts,
    required pw.Font font,
    required AppSettings appSettings,
  }) {
    // الحصول على الأعمدة المرئية مرتبة
    final visibleColumns = appSettings.invoiceDesign.visibleColumns;
    
    // إذا لم تُحدد أعمدة، استخدم الافتراضية
    if (visibleColumns.isEmpty) {
      return pw.SizedBox();
    }

    // بناء خريطة عرض الأعمدة - ترتيب معكوس لـ RTL
    final columnWidths = <int, pw.TableColumnWidth>{};
    for (int i = 0; i < visibleColumns.length; i++) {
      final col = visibleColumns[visibleColumns.length - 1 - i];
      if (col.id == 'details') {
        columnWidths[i] = pw.FlexColumnWidth(col.widthFlex);
      } else {
        columnWidths[i] = pw.FixedColumnWidth(col.widthFlex * 50);
      }
    }

    // بناء رأس الجدول - ترتيب معكوس لـ RTL
    final headerCells = <pw.Widget>[];
    for (int i = visibleColumns.length - 1; i >= 0; i--) {
      final col = visibleColumns[i];
      headerCells.add(_getHeaderCellForDynamic(col.id, col.label, font, appSettings));
    }

    // بناء صفوف البيانات
    final dataRows = pageRows.asMap().entries.map((entry) {
      final index = entry.key + (pageIndex * itemsPerPage);
      final row = entry.value;
      
      if (row['type'] == 'item') {
        final item = row['item'] as InvoiceItem;
        Product? product;
        try {
          product = allProducts.firstWhere((p) => p.name == item.productName);
        } catch (e) {
          product = null;
        }

        // بناء خلايا الصف - ترتيب معكوس لـ RTL
        final rowCells = <pw.Widget>[];
        for (int i = visibleColumns.length - 1; i >= 0; i--) {
          final col = visibleColumns[i];
          rowCells.add(_getDataCellForDynamic(col.id, index, item, product, font, appSettings));
        }
        return pw.TableRow(children: rowCells);
      } else {
        // التسويات (adjustments)
        final a = row['adj'] as InvoiceAdjustment;
        Product? product;
        try {
          product = allProducts.firstWhere((p) => p.id == a.productId);
        } catch (e) {
          product = null;
        }

        // بناء خلايا التسوية - ترتيب معكوس لـ RTL
        final rowCells = <pw.Widget>[];
        for (int i = visibleColumns.length - 1; i >= 0; i--) {
          final col = visibleColumns[i];
          rowCells.add(_getAdjustmentCellForDynamic(col.id, index, a, product, font, appSettings));
        }
        return pw.TableRow(children: rowCells);
      }
    }).toList();

    return pw.Table(
      border: pw.TableBorder.all(width: 0.2),
      columnWidths: columnWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(children: headerCells),
        ...dataRows,
      ],
    );
  }

  /// الحصول على خلية الرأس للعمود المحدد
  pw.Widget _getHeaderCellForDynamic(String columnId, String label, pw.Font font, AppSettings appSettings) {
    switch (columnId) {
      case 'serial':
        return _headerCell(label, font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'productId':
        return _headerCell(label, font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'details':
        return _headerCell(label, font, color: PdfColor.fromInt(appSettings.itemDetailsColor));
      case 'quantity':
        return _headerCell(label, font, color: PdfColor.fromInt(appSettings.itemQuantityColor));
      case 'unitsCount':
        return _headerCell(label, font);
      case 'price':
        return _headerCell(label, font, color: PdfColor.fromInt(appSettings.itemPriceColor));
      case 'amount':
        return _headerCell(label, font, color: PdfColor.fromInt(appSettings.itemTotalColor));
      case 'weight':
        return _headerCell(label, font);
      case 'expiry':
        return _headerCell(label, font);
      default:
        return _headerCell(label, font);
    }
  }

  /// الحصول على خلية البيانات للعمود المحدد (للعناصر العادية)
  pw.Widget _getDataCellForDynamic(String columnId, int index, InvoiceItem item, Product? product, pw.Font font, AppSettings appSettings) {
    final quantity = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0);
    
    switch (columnId) {
      case 'serial':
        return _dataCell('${index + 1}', font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'productId':
        return _dataCell(formatProductId5(product?.id), font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'details':
        return _dataCell(item.productName, font, align: pw.TextAlign.right, color: PdfColor.fromInt(appSettings.itemDetailsColor));
      case 'quantity':
        return _dataCell('${formatNumber(quantity, forceDecimal: true)} ${item.saleType ?? ''}', font, color: PdfColor.fromInt(appSettings.itemQuantityColor));
      case 'unitsCount':
        return _dataCell(InvoicePdfService.buildUnitConversionStringForPdf(item, product), font);
      case 'price':
        return _dataCell(formatNumber(item.appliedPrice, forceDecimal: true), font, color: PdfColor.fromInt(appSettings.itemPriceColor));
      case 'amount':
        return _dataCell(formatNumber(item.itemTotal, forceDecimal: true), font, color: PdfColor.fromInt(appSettings.itemTotalColor));
      case 'weight':
        final weight = product?.baseWeight;
        if (weight != null && weight > 0) {
          final totalWeight = weight * quantity;
          return _dataCell('${formatNumber(totalWeight, forceDecimal: true)} كغ', font);
        }
        return _dataCell('', font);
      case 'expiry':
        // عرض "له صلاحية" بدلاً من علامة لتجنب مشكلة الخط
        if (product?.hasExpiry == true) {
          return _dataCell('له', font);
        }
        return _dataCell('', font);
      default:
        return _dataCell('', font);
    }
  }

  /// الحصول على خلية البيانات للتسويات (adjustments)
  pw.Widget _getAdjustmentCellForDynamic(String columnId, int index, InvoiceAdjustment a, Product? product, pw.Font font, AppSettings appSettings) {
    final double price = a.price ?? 0.0;
    final double qty = a.quantity ?? 0.0;
    final double total = a.amountDelta != 0.0 ? a.amountDelta : (price * qty);
    
    // بناء سلسلة تحويل الوحدات للتسويات
    String getUnitConv() {
      try {
        if (product == null || product.unitHierarchy == null || product.unitHierarchy!.isEmpty) {
          return (a.unitsInLargeUnit?.toString() ?? '');
        }
        final List<dynamic> hierarchy = json.decode(product.unitHierarchy!.replaceAll("'", '"'));
        List<String> factors = [];
        for (int i = 0; i < hierarchy.length; i++) {
          final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
          final quantity = hierarchy[i]['quantity'];
          factors.add(quantity.toString());
          if (unitName == a.saleType) break;
        }
        return factors.isEmpty ? a.unitsInLargeUnit?.toString() ?? '' : factors.join(' × ');
      } catch (_) {
        return a.unitsInLargeUnit?.toString() ?? '';
      }
    }
    
    switch (columnId) {
      case 'serial':
        return _dataCell('${index + 1}', font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'productId':
        return _dataCell(formatProductId5(product?.id), font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'details':
        return _dataCell(a.productName ?? '-', font, align: pw.TextAlign.right, color: PdfColor.fromInt(appSettings.itemDetailsColor));
      case 'quantity':
        return _dataCell('${formatNumber(qty, forceDecimal: true)} ${a.saleType ?? ''}', font, color: PdfColor.fromInt(appSettings.itemQuantityColor));
      case 'unitsCount':
        return _dataCell(getUnitConv(), font);
      case 'price':
        return _dataCell(formatNumber(price, forceDecimal: true), font, color: PdfColor.fromInt(appSettings.itemPriceColor));
      case 'amount':
        return _dataCell(formatNumber(total, forceDecimal: true), font, color: PdfColor.fromInt(appSettings.itemTotalColor));
      case 'weight':
        final weight = product?.baseWeight;
        if (weight != null && weight > 0) {
          final totalWeight = weight * qty;
          return _dataCell('${formatNumber(totalWeight, forceDecimal: true)} كغ', font);
        }
        return _dataCell('', font);
      case 'expiry':
        // عرض "له" بدلاً من علامة لتجنب مشكلة الخط
        if (product?.hasExpiry == true) {
          return _dataCell('له', font);
        }
        return _dataCell('', font);
      default:
        return _dataCell('', font);
    }
  }

// ============================================
// 1. دالة حفظ الفاتورة (saveInvoice)
// ============================================
  // ============================================
  // 1. دالة حفظ الفاتورة (saveInvoice) - Refactored to use InvoiceController
  // ============================================
  Future<Invoice?> saveInvoice({bool printAfterSave = false}) async {
    if (isSaving) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('جاري الحفظ بالفعل...'),
        backgroundColor: Colors.orange,
      ));
      return null;
    }

    if (!formKey.currentState!.validate()) return null;

    final controller = InvoiceController(db: db, storage: storage);

    final inputData = InvoiceInputData(
      invoiceToManage: invoiceToManage,
      customerName: customerNameController.text,
      customerPhone: customerPhoneController.text,
      customerAddress: customerAddressController.text,
      installerName: installerNameController.text,
      paidAmount: double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0,
      loadingFee: double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0,
      discount: discount,
      paymentType: paymentType,
      selectedDate: selectedDate,
      invoiceItems: invoiceItems,
    );

    // 1. Validation
    final validation = controller.validateInvoiceData(inputData);
    if (!validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ في البيانات: ${validation.errorMessage}'),
        backgroundColor: Colors.red,
      ));
      return null;
    }

    // 2. Debt Validation
    final debtValidation = await controller.validateDebtChangeWontCauseNegativeBalance(inputData);
    if (!debtValidation.isValid) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('⚠️ تحذير مالي', style: TextStyle(color: Colors.red)),
            content: Text(debtValidation.errorMessage ?? ''),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      }
      return null;
    }

    setState(() {
      isSaving = true;
    });

    // 🔒 إلغاء أي تزامن حي معلّق لمنع race condition مع الحفظ
    (this as dynamic).liveDebtTimer?.cancel();

    try {
      final result = await controller.saveInvoice(inputData);

      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Unknown error');
      }

      final savedInvoice = result.invoice;

      savedOrSuspended = true;
      hasUnsavedChanges = false;

      // ⚡ رفع فوري لحزمة الفاتورة (فاتورة + عميل + معاملات) ثم رفع وثيقة العميل.
      //    fire-and-forget: لا نُعلّق تجربة المستخدم على نتيجة الشبكة.
      if (savedInvoice != null) {
        final invoiceUuid = savedInvoice.invoiceUuid;
        final customerId = savedInvoice.customerId;
        () async {
          try {
            if (invoiceUuid != null && invoiceUuid.isNotEmpty) {
              final ok = await InvoiceSyncService().syncInvoiceBundleNow(invoiceUuid);
              if (!ok) {
                print('⚠️ الرفع الفوري تأجّل (سيلتقطه المؤقت الدوري لاحقاً)');
              }
            }
            if (customerId != null && customerId != 0) {
              final customer = await db.getCustomerById(customerId);
              if (customer != null &&
                  customer.syncUuid != null &&
                  customer.syncUuid!.isNotEmpty) {
                await FirebaseSyncHelper().syncCustomer(customer.toMap());
              }
            }
          } catch (e) {
            print('⚠️ الرفع الفوري تأجّل: $e');
          }
        }();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                inputData.isNewInvoice ? 'تم حفظ الفاتورة بنجاح' : 'تم تعديل الفاتورة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );

        // Update UI with fresh data
        if (savedInvoice != null && savedInvoice.id != null) {
          try {
            final freshItems = await db.getInvoiceItems(savedInvoice.id!);
            for (var item in freshItems) {
              item.initializeControllers();
            }
            setState(() {
              invoiceItems.clear();
              invoiceItems.addAll(freshItems);
              invoiceToManage = savedInvoice;
              isViewOnly = true;
            });
          } catch (e) {
            setState(() {
              invoiceToManage = savedInvoice;
              isViewOnly = true;
            });
          }
        } else {
           setState(() {
              invoiceToManage = savedInvoice;
              isViewOnly = true;
            });
        }

        if (inputData.isNewInvoice) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }

      return savedInvoice;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل حفظ الفاتورة: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

// ============================================
// 2. دالة إنشاء PDF (generateInvoicePdf)// ============================================
  Future<pw.Document> generateInvoicePdf() async {
    try {
      final pdf = pw.Document();

      final appSettings = await SettingsManager.getAppSettings();

      // تحميل اللوجو باستخدام خدمة اللوجو (مخصص أو افتراضي)
      final logoImage = await LogoService.getLogoImage(appSettings: appSettings);
      final font =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
      final alnaserFont =
          pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
      
      // ═══════════════════════════════════════════════════════════════════════════
      // 🔧 إصلاح: جلب الأصناف من قاعدة البيانات لضمان عرض البيانات المحدثة
      // ═══════════════════════════════════════════════════════════════════════════
      List<InvoiceItem> itemsForPdf = invoiceItems;
      if (invoiceToManage != null && invoiceToManage!.id != null) {
        try {
          final freshItems = await db.getInvoiceItems(invoiceToManage!.id!);
          if (freshItems.isNotEmpty) {
            itemsForPdf = freshItems;
          }
        } catch (e) {
          // استخدام الأصناف من الذاكرة في حالة الفشل
        }
      }

      String buildUnitConversionStringForPdf(InvoiceItem item, Product? product) {
        if (item.unit == 'meter') {
          if (item.saleType == 'لفة' && item.unitsInLargeUnit != null) {
            return item.unitsInLargeUnit!.toString();
          } else {
            return '';
          }
        }
        if (item.saleType == 'قطعة' || item.saleType == 'متر') {
          return '';
        }
        if (product == null ||
            product.unitHierarchy == null ||
            product.unitHierarchy!.isEmpty) {
          return item.unitsInLargeUnit?.toString() ?? '';
        }
        try {
          final List<dynamic> hierarchy =
              json.decode(product.unitHierarchy!.replaceAll("'", '"'));
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

      final allProducts = await db.getAllProducts();
      final filteredItems =
          itemsForPdf.where((item) => _isInvoiceItemComplete(item)).toList();

      final itemsTotal =
          filteredItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final discount = this.discount;
      final double loadingFee =
          double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
              0.0;

      List<InvoiceAdjustment> adjs = [];
      double settlementsTotal = 0.0;
      if (invoiceToManage != null && invoiceToManage!.id != null) {
        try {
          adjs = await db.getInvoiceAdjustments(invoiceToManage!.id!);
          settlementsTotal = adjs.fold(0.0, (sum, a) => sum + a.amountDelta);
        } catch (_) {}
      }
      final bool hasAdjustments = adjs.isNotEmpty;
      final DateTime invoiceDateOnly = DateTime(
          selectedDate.year, selectedDate.month, selectedDate.day);
      final List<InvoiceAdjustment> sameDayAddedItemAdjs = adjs.where((a) {
        if (a.productId == null) return false;
        if (a.type != 'debit') return false;
        final d =
            DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day);
        return d == invoiceDateOnly;
      }).toList();
      final List<InvoiceAdjustment> itemAdditionsForSection = adjs
          .where((a) =>
              a.productId != null &&
              a.type == 'debit' &&
              !sameDayAddedItemAdjs.contains(a))
          .toList();
      final List<InvoiceAdjustment> itemCreditsForSection =
          adjs.where((a) => a.productId != null && a.type == 'credit').toList();
      final List<InvoiceAdjustment> amountOnlyAdjs =
          adjs.where((a) => a.productId == null).toList();
      final bool showSettlementSections = itemAdditionsForSection.isNotEmpty ||
          itemCreditsForSection.isNotEmpty ||
          amountOnlyAdjs.isNotEmpty ||
          sameDayAddedItemAdjs.isNotEmpty;

      final bool includeSameDayOnlyCase =
          sameDayAddedItemAdjs.isNotEmpty && !showSettlementSections;

      final double sameDayAddsTotal =
          sameDayAddedItemAdjs.fold(0.0, (sum, a) {
        final double price = a.price ?? 0.0;
        final double quantity = a.quantity ?? 0.0;
        return sum + (price * quantity);
      });
      final double itemsTotalForDisplay =
          includeSameDayOnlyCase ? (itemsTotal + sameDayAddsTotal) : itemsTotal;
      final double settlementsTotalForDisplay =
          includeSameDayOnlyCase ? 0.0 : settlementsTotal;
      final double preDiscountTotal =
          (itemsTotalForDisplay + settlementsTotalForDisplay + loadingFee);
      final double afterDiscount =
          ((preDiscountTotal - discount).clamp(0.0, double.infinity)).toDouble();

        final double paid =
            double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
                0.0;
        final isCash = paymentType == 'نقد';

      final double cashSettlements = showSettlementSections
          ? [...adjs, ...sameDayAddedItemAdjs]
              .where((a) => a.settlementPaymentType == 'نقد')
              .fold(0.0, (sum, a) {
              if (a.productId != null) {
                final double price = a.price ?? 0.0;
                final double quantity = a.quantity ?? 0.0;
                return sum + (price * quantity);
              } else {
                return sum + a.amountDelta;
              }
            })
          : 0.0;
      final double debtSettlements = showSettlementSections
          ? [...adjs, ...sameDayAddedItemAdjs]
              .where((a) => a.settlementPaymentType == 'دين')
              .fold(0.0, (sum, a) {
              if (a.productId != null) {
                final double price = a.price ?? 0.0;
                final double quantity = a.quantity ?? 0.0;
                return sum + (price * quantity);
              } else {
                return sum + a.amountDelta;
              }
            })
          : 0.0;

      double displayedPaidForSettlementsCase;
      if (isCash && !showSettlementSections) {
        displayedPaidForSettlementsCase = afterDiscount;
      } else {
        displayedPaidForSettlementsCase = paid + cashSettlements;
      }

      double previousDebt = 0.0;
      double currentDebt = 0.0;
        final customerName = customerNameController.text.trim();
        final customerPhone = customerPhoneController.text.trim();
        if (customerName.isNotEmpty) {
          final customers = await db.searchCustomers(customerName);
        Customer? matchedCustomer;
        if (customerPhone.isNotEmpty) {
          matchedCustomer = customers.firstWhere(
            (c) =>
                c.name.trim() == customerName &&
                (c.phone ?? '').trim() == customerPhone,
            orElse: () => Customer(
                id: null,
                name: '',
                phone: null,
                address: null,
                createdAt: DateTime.now(),
                lastModifiedAt: DateTime.now(),
                currentTotalDebt: 0.0), // Dummy to avoid exception
          );
          if (matchedCustomer?.name == '' || matchedCustomer == null) matchedCustomer = null;
        } else {
          matchedCustomer = customers.firstWhere(
            (c) => c.name.trim() == customerName,
            orElse: () => Customer(
                id: null,
                name: '',
                phone: null,
                address: null,
                createdAt: DateTime.now(),
                lastModifiedAt: DateTime.now(),
                currentTotalDebt: 0.0), // Dummy
          );
          if (matchedCustomer?.name == '' || matchedCustomer == null) matchedCustomer = null;
        }
        if (matchedCustomer != null) {
          previousDebt = matchedCustomer.currentTotalDebt;
        }
      }

      final double remainingForPdf;
      if (isCash && !showSettlementSections) {
        remainingForPdf = 0;
      } else {
        remainingForPdf = afterDiscount - displayedPaidForSettlementsCase;
      }

      if (showSettlementSections) {
        currentDebt = previousDebt + debtSettlements;
      } else {
        if (isCash) {
          currentDebt = previousDebt;
        } else {
          currentDebt = previousDebt + remainingForPdf;
        }
      }

        final double currentDebtForPdf =
            (invoiceToManage != null && invoiceToManage!.status == 'محفوظة')
                ? previousDebt
                : currentDebt;

      // بناء رقم الفاتورة للعرض (الرقم المركّب الصحيح)
      String invoiceDisplayNumber;
      if (invoiceToManage != null && invoiceToManage!.id != null) {
        invoiceDisplayNumber = invoiceToManage!.formattedInvoiceNumber;
      } else {
        invoiceDisplayNumber = await db.getNextInvoiceNumber(selectedDate);
      }

      final List<Map<String, dynamic>> combinedRows = [
        ...filteredItems.map((it) => {'type': 'item', 'item': it}),
        if (includeSameDayOnlyCase)
          ...sameDayAddedItemAdjs.map((a) => {'type': 'adj', 'adj': a}),
      ];

      const itemsPerPage = 19;
      final totalPages =
          (combinedRows.length / itemsPerPage).ceil().clamp(1, double.infinity).toInt();
      bool printedSummaryInLastPage = false;

      for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        final start = pageIndex * itemsPerPage;
        final end = (start + itemsPerPage) > combinedRows.length
            ? combinedRows.length
            : start + itemsPerPage;
        final pageRows = combinedRows.sublist(start, end);

        final bool isLast = pageIndex == totalPages - 1;
        final bool deferSummary =
            isLast && (pageRows.length >= 17) && showSettlementSections;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.only(top: 0, bottom: 2, left: 10, right: 10),
            build: (pw.Context context) {
              return pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Stack(
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        buildPdfHeader(font, alnaserFont, logoImage,
                            appSettings: appSettings),
                        pw.SizedBox(height: 4),
                        // صف معلومات الفاتورة مع مساحات محددة
                        _buildInvoiceInfoRow(
                          font: font,
                          customerName: customerNameController.text,
                          customerAddress: customerAddressController.text,
                          customerPhone: customerPhoneController.text.trim(),
                          invoiceDisplayNumber: invoiceDisplayNumber,
                          selectedDate: selectedDate,
                          createdAt: invoiceToManage?.createdAt,
                        ),
                        pw.Divider(height: 5, thickness: 0.5),
                        // جدول الفاتورة الديناميكي بناءً على إعدادات الأعمدة
                        _buildDynamicTableForPdf(
                          pageRows: pageRows,
                          pageIndex: pageIndex,
                          itemsPerPage: itemsPerPage,
                          allProducts: allProducts,
                          font: font,
                          appSettings: appSettings,
                        ),
                        pw.Divider(height: 4, thickness: 0.4),
                        if (isLast && !deferSummary) ...[
                          if (invoiceToManage != null &&
                              invoiceToManage!.id != null &&
                              (itemAdditionsForSection.isNotEmpty ||
                                  itemCreditsForSection.isNotEmpty ||
                                  amountOnlyAdjs.isNotEmpty)) ...[
                            // ... (All settlement sections code)
                          ],
                          pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.end,
                                  children: [
                                    _summaryRow("الإجمالي قبل الخصم", preDiscountTotal, font,
                                        color: PdfColor.fromInt(appSettings.totalBeforeDiscountColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("الخصم", discount, font,
                                        color: PdfColor.fromInt(appSettings.discountColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("الإجمالي بعد الخصم", afterDiscount, font,
                                        color: PdfColor.fromInt(appSettings.totalAfterDiscountColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("المبلغ المدفوع", displayedPaidForSettlementsCase, font,
                                        color: PdfColor.fromInt(appSettings.paidAmountColor)),
                                  ],
                                ),
                                pw.SizedBox(height: 4),
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.end,
                                  children: [
                                    _summaryRow("المبلغ المتبقي", remainingForPdf, font,
                                        color: PdfColor.fromInt(appSettings.remainingAmountColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("المبلغ المطلوب الحالي", currentDebtForPdf, font,
                                        color: PdfColor.fromInt(appSettings.currentDebtColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("أجور التحميل", loadingFee, font,
                                        color: PdfColor.fromInt(appSettings.loadingFeesColor)),
                                  ],
                                ),
                              ]),
                          pw.SizedBox(height: 6),
                          pw.Align(
                              child: pw.Text(
                                  'تنويه: أي ملاحظات على تجهيز المواد تُقبل خلال 3 أيام من تاريخ الفاتورة فقط  وشكراً لتعاملكم معنا',
                                  style: pw.TextStyle(
                                      font: font,
                                      fontSize: 11,
                                      color: PdfColor.fromInt(
                                          appSettings.noticeColor)))),
                        ],
                        pw.Spacer(),
                        pw.Align(
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            'صفحة ${pageIndex + 1} من $totalPages',
                            style: pw.TextStyle(font: font, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    pw.Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: pw.Container(
                        alignment: pw.Alignment.topLeft,
                        padding: const pw.EdgeInsets.only(top: 250, left: 0),
                        child: pw.Transform.rotate(
                          angle: 0.8,
                          child: pw.Opacity(
                            opacity: 0.11,
                          child: pw.Text(
                            appSettings.invoiceDesign.companyName,
                            style: pw.TextStyle(
                                font: alnaserFont,
                                fontSize: 200,
                                color: PdfColors.grey400,
                                fontWeight: pw.FontWeight.bold,
                                fontFallback: [font],
                            ),
                          ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
        if (isLast && !deferSummary) {
          printedSummaryInLastPage = true;
        }
      }

      if (!printedSummaryInLastPage) {
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.only(top: 10, bottom: 10, left: 10, right: 10),
          build: (pw.Context context) {
            // Logic for the deferred summary page
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text("ملخص الفاتورة",
                    style:
                        pw.TextStyle(font: font, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Divider(),
                // Re-add your summary rows here
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    _summaryRow("الإجمالي قبل الخصم", preDiscountTotal, font,
                        color: PdfColor.fromInt(appSettings.totalBeforeDiscountColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("الخصم", discount, font,
                        color: PdfColor.fromInt(appSettings.discountColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("الإجمالي بعد الخصم", afterDiscount, font,
                        color: PdfColor.fromInt(appSettings.totalAfterDiscountColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("المبلغ المدفوع", displayedPaidForSettlementsCase, font,
                        color: PdfColor.fromInt(appSettings.paidAmountColor)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    _summaryRow("المبلغ المتبقي", remainingForPdf, font,
                        color: PdfColor.fromInt(appSettings.remainingAmountColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("المبلغ المطلوب الحالي", currentDebtForPdf, font,
                        color: PdfColor.fromInt(appSettings.currentDebtColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("أجور التحميل", loadingFee, font,
                        color: PdfColor.fromInt(appSettings.loadingFeesColor)),
                  ],
                ),
              ],
            );
          },
        ));
      }
      return pdf;
    } catch (e) {
      print('Error generating PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إنشاء ملف PDF: $e')),
        );
      }
      rethrow;
    }
  }

// ========================================
// 
// ====
// 3. دالة طباعة الفاتورة (printInvoice)
// ============================================
  Future<void> printInvoice() async {
    try {
      final pdf = await generateInvoicePdf();
      if (Platform.isWindows) {
        final filePath = await saveInvoicePdf(
            pdf, customerNameController.text, selectedDate);
        await Process.start('cmd', ['/c', 'start', '/min', '', filePath]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال الفاتورة للطابعة مباشرة!')),
          );
        }
        return;
      }
      if (Platform.isAndroid) {
        if (selectedPrinter == null) {
          List<PrinterDevice> printers = [];
          final bluetoothPrinters =
              await printingService.findBluetoothPrinters();
          final systemPrinters =
              await printingService.findSystemPrinters();
          printers = [...bluetoothPrinters, ...systemPrinters];
          if (printers.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('لا توجد طابعات متاحة.')),
              );
            }
            return;
          }
          final selected = await showDialog<PrinterDevice>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('اختر الطابعة'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: printers.length,
                    itemBuilder: (context, index) {
                      final printer = printers[index];
                      return ListTile(
                        title: Text(printer.name),
                        subtitle: Text(printer.connectionType.name),
                        onTap: () => Navigator.of(context).pop(printer),
                      );
                    },
                  ),
                ),
              );
            },
          );
          if (selected == null) return;
          setState(() {
            selectedPrinter = selected;
          });
        }
        if (selectedPrinter != null) {
          try {
            await printingService.printData(
              await pdf.save(),
              printerDevice: selectedPrinter,
              escPosCommands: null,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'تم إرسال الفاتورة إلى الطابعة: ${selectedPrinter!.name}')),
              );
            }
          } catch (e) {
            print('Error during print: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('حدث خطأ أثناء الطباعة: ${e.toString()}')),
              );
            }
          }
        }
        return;
      }
    } catch (e) {
      print('Error printing invoice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الطباعة: $e')),
        );
      }
    }
  }

// ============================================
// 4. دالة مشاركة الفاتورة (shareInvoice)
// ============================================
  Future<void> shareInvoice() async {
    try {
      final pdf = await generateInvoicePdf();
      final filePath = await saveInvoicePdfToTemp(
          pdf, customerNameController.text, selectedDate);
      final fileName = p.basename(filePath);
      await Share.shareXFiles([
        XFile(filePath, mimeType: 'application/pdf', name: fileName)
      ], text: 'فاتورة ${customerNameController.text}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل مشاركة الفاتورة: $e')),
        );
      }
    }
  }
}

// Helper function that might be in another file, but is needed for the PDF generation.
String formatProductId5(int? id) {
  if (id == null) return '-----';
  return id.toString().padLeft(5, '0');
}

// ═══════════════════════════════════════════════════════════════════════════
// 🔒 نتيجة التحقق الداخلية
// ═══════════════════════════════════════════════════════════════════════════
class _ValidationResult {
  final bool isValid;
  final String? errorMessage;
  
  _ValidationResult({required this.isValid, this.errorMessage});
}
