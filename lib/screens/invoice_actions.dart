// lib/screens/invoice_actions.dart
import '../services/save_lock.dart'; // 🔒 قفل الحفظ
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐
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
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/invoice_adjustment.dart';
import '../models/invoice_item.dart';
import '../models/printer_device.dart';
import '../models/product.dart';
import '../models/invoice_input_data.dart'; // ✅ Added import
import '../services/database_service.dart';
import '../wa_messages/wa_doc_sender.dart'; // 📨 إرسال عبر واتساب
import '../services/credit_limit_guard.dart'; // 🚫 سقف الدين
import '../services/database/business/customer_name_rule.dart'; // 🔤 الاسم بلا مسافات
// import '../services/drive_service.dart'; // Removed
import '../services/printed_invoice_pdf.dart'; // 🖨️ التصميم الأصلي الموحّد (طباعة + تيليجرام)
import '../erp/sales/roll_invoice_pdf.dart'; // 🧾 طباعة 80mm
import '../invoice_designer/designed_rows.dart'; // 🎨 مصمم الفاتورة
import '../invoice_designer/invoice_layout_store.dart';
import '../invoice_designer/invoice_print_data.dart';
import '../invoice_designer/layout_pdf_renderer.dart';
import '../services/printing_service.dart';
import '../services/settings_manager.dart';
import '../services/auth_service.dart'; // 👤 User authentication
import '../org/warehouse_scope.dart'; // 🔐 نطاق الموظف
import '../services/debt_reminders.dart'; // 📅
import '../services/product_codes.dart'; // 🏷️ رمز المادة
import '../services/logo_service.dart'; // 🖼️ Custom logo loading
import 'create_invoice_screen.dart';
import '../controllers/invoice_controller.dart';
import '../services/voucher_print.dart'; // 🧾 سندات التعديل بالقلم ومصمم السندات
import '../erp/control/approval_gate.dart'; // ✅ موافقة المدير قبل العمليات الحساسة
import '../erp/control/print_audit.dart'; // 🖨️ تتبّع طباعة الفواتير
import '../services/invoice_edit_voucher.dart'; // 🧾 سند مرتجع/إضافة للفاتورة النقدية
import '../services/invoice_staff_service.dart'; // 👷 المجهز والمحاسب
import '../services/firebase_sync/invoice_sync_service.dart'; // ⚡ رفع فوري بعد الحفظ
import '../services/firebase_sync/firebase_sync_helper.dart';
import '../owner/owner_access.dart';
import '../owner/founder_service.dart';

/// واجهة تحدد المتغيرات المطلوبة للتعامل مع الفواتير
abstract class InvoiceActionsInterface {
  /// 🔒 اسم العميل محجوز لهذا الجهاز؟ null = نعم، وإلا رسالة المنع
  Future<String?> verifyCustomerClaimBeforeSave();

  bool get isSaving;
  set isSaving(bool value);
  
  GlobalKey<FormState> get formKey;
  
  Invoice? get invoiceToManage;
  set invoiceToManage(Invoice? value);
  
  TextEditingController get customerNameController;
  TextEditingController get customerPhoneController;
  TextEditingController get customerAddressController;
  TextEditingController get installerNameController;

  /// 👷 المجهز والمحاسب (من «المزيد»)
  TextEditingController get preparerController;
  TextEditingController get accountantController;

  /// 👷 نقاط المؤسس لكل 100,000 لهذه الفاتورة
  double get founderPointsRate;
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


  bool _isInvoiceItemComplete(InvoiceItem item) {
    // التحقق من أن الكمية موجودة وأكبر من صفر
    final hasValidQuantity = (item.quantityIndividual != null && item.quantityIndividual! > 0) ||
                             (item.quantityLargeUnit != null && item.quantityLargeUnit! > 0);
    return (item.productName.isNotEmpty &&
        hasValidQuantity &&
        (item.appliedPrice > 0 || item.isGift) && // 🎁 الهدية سعرها صفر
        (item.itemTotal > 0 || item.isGift) &&
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
      debugPrint('Error saving PDF: $e');
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


// ============================================
// 1. دالة حفظ الفاتورة (saveInvoice)
// ============================================
  // ============================================
  // 1. دالة حفظ الفاتورة (saveInvoice) - Refactored to use InvoiceController
  // ============================================
  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<Invoice?> saveInvoice({bool printAfterSave = false}) async =>
      await SaveLock.run<Invoice?>(() => _saveInvoiceUnlocked(printAfterSave: printAfterSave), message: 'جارٍ حفظ الفاتورة…');
  Future<Invoice?> _saveInvoiceUnlocked({bool printAfterSave = false}) async {
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
      installerName: installerNameController.text.trim(),
      // غير المالك لا يرى حقل المؤسس: يبقى ما في الفاتورة كما هو
      pointsRate: OwnerAccess.enabled ? founderPointsRate : (invoiceToManage?.pointsRate ?? 0.0),
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

    // 🚫 سقف الدين: فاتورة آجلة جديدة، أو زيادة دين فاتورة عند تعديلها (الفرق فقط)
    {
      final dbx = await db.database;
      final old = inputData.invoiceToManage;
      final sameName = old != null &&
          old.customerName.trim().replaceAll(' ', '') == inputData.customerName.trim().replaceAll(' ', '');
      final int? cid = (sameName && old.customerId != null)
          ? old.customerId
          : await CreditLimitGuard.customerIdByName(dbx, inputData.customerName);
      if (cid != null) {
        final complete = inputData.invoiceItems.where((it) =>
            it.productName.isNotEmpty &&
            ((it.quantityIndividual ?? 0) > 0 || (it.quantityLargeUnit ?? 0) > 0) &&
            (it.appliedPrice > 0 || it.isGift) &&
            (it.itemTotal > 0 || it.isGift) &&
            (it.saleType ?? '').isNotEmpty);
        final total =
            complete.fold<double>(0, (s, it) => s + it.itemTotal) + inputData.loadingFee - inputData.discount;
        final increase = await CreditLimitGuard.invoiceIncrease(
          dbx,
          customerId: cid,
          credit: inputData.paymentType != 'نقد',
          total: total,
          paid: inputData.paidAmount,
          editInvoiceId: sameName ? old.id : null,
        );
        if (!mounted) return null;
        final go = await CreditLimitGuard.enforce(
          context,
          customerId: cid,
          increase: increase,
          what: '${old == null ? 'فاتورة جديدة' : 'تعديل فاتورة'} — ${inputData.customerName.trim()}',
        );
        if (!go) return null;
      }
    }

    // ✅ موافقة المدير قبل الحفظ: تاريخ سابق، بيع تحت الكلفة، خصم أعلى من المسموح
    //    (المدير المسجّل لا يُسأل؛ التسوية على فاتورة سابقة ليست «تعديلاً» لتاريخها)
    {
      if (!mounted) return null;
      final settlement = widget.settlementForInvoice != null;
      final old = settlement ? null : inputData.invoiceToManage;
      final go = await ApprovalGate.checkInvoice(
        context,
        items: inputData.invoiceItems,
        discount: inputData.discount,
        selectedDate: settlement ? DateTime.now() : inputData.selectedDate,
        originalDate: old?.invoiceDate,
        invoiceId: old?.id,
        customerName: inputData.customerName,
      );
      if (!go) return null;
    }

    // 🔐 الموظف المقيَّد بمخازن: مخزن هذا الجهاز يجب أن يكون من مخازنه
    {
      final block = await WarehouseScope.saleBlockReason();
      if (block != null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(block), backgroundColor: Colors.red.shade700));
        }
        return null;
      }
    }

    setState(() {
      isSaving = true;
    });

    // 🔒 اسم العميل قيد الاستعمال في فاتورة مفتوحة على جهاز آخر؟ لا حفظ
    final claimMsg = await verifyCustomerClaimBeforeSave();
    if (claimMsg != null) {
      if (mounted) {
        setState(() => isSaving = false);
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('⛔ العميل مستخدم على جهاز آخر'),
            content: Text(claimMsg, style: const TextStyle(height: 1.6)),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
          ),
        );
      }
      return null;
    }

    // 🔒 إلغاء أي تزامن حي معلّق لمنع race condition مع الحفظ
    (this as dynamic).liveDebtTimer?.cancel();

    // 🧾 مجموع الفاتورة المحفوظة ونوع دفعها قبل التعديل (لسند المرتجع/الإضافة)
    final editId = inputData.isNewInvoice ? null : inputData.invoiceToManage?.id;
    final beforeEdit = editId == null ? null : await InvoiceEditVoucher.snapshot(editId);

    try {
      final result = await controller.saveInvoice(inputData);

      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Unknown error');
      }

      final savedInvoice = result.invoice;

      // 👷 مؤسس جديد كُتب اسمه في الفاتورة ⇒ يُسجَّل في قائمة المؤسسين
      final founderName = savedInvoice?.installerName?.trim() ?? '';
      if (OwnerAccess.enabled && founderName.isNotEmpty) {
        FounderService.ensureFounder(founderName).catchError((_) => null);
      }
      // 📥 فاتورة مستوردة عُدّلت: نقاطها من الفاتورة نفسها من الآن (لا من السجل القديم)
      final savedId = savedInvoice?.id;
      // 👷 المجهز والمحاسب
      if (savedId != null) {
        InvoiceStaff.save(savedId,
                preparer: preparerController.text, accountant: accountantController.text)
            .catchError((_) {});
      }
      if (savedId != null) FounderService.refreshInvoicePoints(savedId).catchError((_) => null);

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
                debugPrint('⚠️ الرفع الفوري تأجّل (سيلتقطه المؤقت الدوري لاحقاً)');
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
            debugPrint('⚠️ الرفع الفوري تأجّل: $e');
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

        // 🧾 فاتورة نقدية عُدّلت: يُحفظ سجل السند النقدي (يقرؤه تقرير المال الفعلي)
        int? legacyCashVoucherId;
        if (editId != null && beforeEdit != null && savedInvoice != null) {
          try {
            legacyCashVoucherId = await InvoiceEditVoucher.recordIfCash(
              invoiceId: editId,
              before: beforeEdit,
              totalAfter: savedInvoice.totalAmount,
              paymentAfter: savedInvoice.paymentType,
              user: AuthService().currentUser?.username,
            );
          } catch (e) {
            debugPrint('⚠️ سند تعديل الفاتورة: $e');
          }
        }

        // 🧾 التعديل بالقلم عملية بتاريخ اليوم: سنده حسب نوعه — نقدية: سند قبض (إضافة) أو
        //    سند صرف (مرتجع)؛ آجلة: إشعار مدين أو دائن. الطباعة حسب إعداد كل نوع.
        final editEventId = result.editEventId;
        if (editEventId != null && mounted) {
          try {
            await VoucherPrint.offerEditEvent(context, editEventId, legacyCashVoucherId: legacyCashVoucherId);
          } catch (e) {
            debugPrint('⚠️ سند التعديل: $e');
          }
        }

        // 📅 موعد مطالبة حُدد من «المزيد» قبل الحفظ: يُربط بالفاتورة الآن
        if (savedInvoice != null) await DebtReminders.commitPending(savedInvoice);

        // 🖨️ طباعة تلقائية بعد الحفظ (من «المزيد» في شاشة الفاتورة) — مثل الإداري
        var autoPrint = printAfterSave;
        if (!autoPrint) {
          try {
            final prefs = await SharedPreferences.getInstance();
            autoPrint = prefs.getBool('invoice_auto_print_after_save') ?? false;
          } catch (_) {}
        }
        if (autoPrint && mounted && savedInvoice != null) {
          try {
            await printInvoice();
          } catch (e) {
            debugPrint('⚠️ الطباعة بعد الحفظ: $e');
          }
        }

        if (inputData.isNewInvoice && mounted) {
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
  /// 📦 وثيقة التجهيز بتصميم من «مصمم الفاتورة» إن رُبط تصميم بـ«وثيقة التجهيز»؛
  /// null ⇒ الشكل الأصلي. لا سعر ولا مبلغ يصل التصميم أبداً: أعمدة السعر والمبلغ
  /// والخصم فارغة، والمجاميع والدين ونوع الدفع غير مرسلة.
  Future<pw.Document?> generateDesignedPickingPdf() async {
    final designed = await InvoiceLayoutStore.activeFor(PrintTarget.pickingA4.key);
    if (designed == null) return null;
    final appSettings = await SettingsManager.getAppSettings();
    final allProducts = await db.getAllProducts();
    Product? byName(String n) {
      for (final p in allProducts) {
        if (p.name == n) return p;
      }
      return null;
    }

    const money = ['price', 'amount', 'priceBeforeDiscount', 'discount'];
    final items = invoiceItems.where((it) => it.productName.trim().isNotEmpty).toList();
    final rows = <Map<String, String>>[
      for (var i = 0; i < items.length; i++)
        {
          ...DesignedRows.item(i, items[i], byName(items[i].productName)),
          for (final k in money) k: '',
        },
    ];
    final created = invoiceToManage?.createdAt ?? DateTime.now();
    final dateStr = InvoicePrintData.dateText(selectedDate);
    final invoiceNo = (invoiceToManage != null && invoiceToManage!.id != null)
        ? invoiceToManage!.formattedInvoiceNumber
        : await db.getNextInvoiceNumber(selectedDate);
    return LayoutPdfRenderer.render(
      designed,
      InvoicePrintData(
        company: await PrintCompany.load(appSettings),
        fields: {
          'invoiceNo': invoiceNo,
          'date': dateStr,
          'time': InvoicePrintData.timeText(created),
          'dateTime': '$dateStr ${InvoicePrintData.timeText(created)}',
          'customer': customerNameController.text.trim(),
          'phone': customerPhoneController.text.trim(),
          'address': customerAddressController.text.trim(),
          'user': AuthService().currentUser?.username ?? '',
          'preparer': preparerController.text.trim(),
          'accountant': accountantController.text.trim(),
          'copy': '',
        },
        rows: rows,
        totals: const {}, // لا مبالغ في وثيقة التجهيز
        paymentType: '',
      ),
    );
  }

  Future<pw.Document> generateInvoicePdf({String target = 'invoice_a4'}) async {
    try {
      final pdf = pw.Document();

      final appSettings = await SettingsManager.getAppSettings();
      await ProductCodes.refresh(); // 🏷️ رموز المواد للطباعة (أحدث نسخة)

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
        if (customerName.isNotEmpty) {
          // 🔤 نفس قاعدة الحفظ: الاسم بلا مسافات يحدد الحساب، والهاتف لا يفرّق
          final nameKey = CustomerNameRule.key(customerName);
          final customers = await db.searchCustomers(customerName);
          Customer? matchedCustomer;
          for (final c in customers) {
            if (CustomerNameRule.key(c.name.trim()) == nameKey) {
              matchedCustomer = c;
              break;
            }
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

      // 🎨 تصميم من «مصمم الفاتورة» مختار لهذا النوع من الطباعة؟ (وإلا التصميم الأصلي أدناه)
      final designed = await InvoiceLayoutStore.activeFor(target);
      if (designed != null) {
        Product? byName(String n) {
          for (final p in allProducts) {
            if (p.name == n) return p;
          }
          return null;
        }

        Product? byId(int? id) {
          if (id == null) return null;
          for (final p in allProducts) {
            if (p.id == id) return p;
          }
          return null;
        }

        final rows = <Map<String, String>>[];
        for (var i = 0; i < combinedRows.length; i++) {
          final r = combinedRows[i];
          if (r['type'] == 'item') {
            final it = r['item'] as InvoiceItem;
            rows.add(DesignedRows.item(i, it, byName(it.productName)));
          } else {
            final a = r['adj'] as InvoiceAdjustment;
            rows.add(DesignedRows.adjustment(i, a, byId(a.productId)));
          }
        }
        final created = invoiceToManage?.createdAt ?? DateTime.now();
        final dateStr = InvoicePrintData.dateText(selectedDate);
        return LayoutPdfRenderer.render(
          designed,
          InvoicePrintData(
            company: await PrintCompany.load(appSettings),
            fields: {
              'invoiceNo': invoiceDisplayNumber,
              'date': dateStr,
              'time': InvoicePrintData.timeText(created),
              'dateTime': '$dateStr ${InvoicePrintData.timeText(created)}',
              'customer': customerNameController.text.trim(),
              'phone': customerPhoneController.text.trim(),
              'address': customerAddressController.text.trim(),
              'paymentType': paymentType,
              'user': AuthService().currentUser?.username ?? '',
              'preparer': preparerController.text.trim(),
              // 👤 المحاسب = من سجّل الفاتورة (لا من يطبعها الآن)؛ من يطبع في «طُبع بواسطة»
              'accountant': accountantController.text.trim().isNotEmpty
                  ? accountantController.text.trim()
                  : ((invoiceToManage?.createdByUsername ?? '').trim().isNotEmpty
                      ? await VoucherPrint.displayNameOf(await db.database, invoiceToManage!.createdByUsername)
                      : (AuthService().currentUser?.shownName ?? '')),
              'copy': '',
            },
            rows: rows,
            totals: {
              'beforeDiscount': preDiscountTotal,
              'discount': discount,
              'afterDiscount': afterDiscount,
              'loadingFee': loadingFee,
              'net': afterDiscount,
              'paid': displayedPaidForSettlementsCase,
              'remaining': remainingForPdf,
              'previousDebt': previousDebt,
              'currentDebt': currentDebtForPdf,
            },
            paymentType: paymentType,
          ),
        );
      }

      // 🖨️ التصميم الأصلي من المصدر الموحّد — نفسه الذي يُرسل إلى تيليجرام
      await PrintedInvoicePdf.addOriginalPages(
        pdf,
        font: font,
        alnaserFont: alnaserFont,
        logoImage: logoImage,
        appSettings: appSettings,
        combinedRows: combinedRows,
        itemsForPdf: itemsForPdf,
        allProducts: allProducts,
        showSettlementSections: showSettlementSections,
        itemAdditionsForSection: itemAdditionsForSection,
        itemCreditsForSection: itemCreditsForSection,
        amountOnlyAdjs: amountOnlyAdjs,
        invoiceDisplayNumber: invoiceDisplayNumber,
        customerName: customerNameController.text,
        customerAddress: customerAddressController.text,
        customerPhone: customerPhoneController.text.trim(),
        selectedDate: selectedDate,
        invoiceToManage: invoiceToManage,
        preDiscountTotal: preDiscountTotal,
        discount: discount,
        afterDiscount: afterDiscount,
        loadingFee: loadingFee,
        displayedPaidForSettlementsCase: displayedPaidForSettlementsCase,
        remainingForPdf: remainingForPdf,
        currentDebtForPdf: currentDebtForPdf,
      );
      return pdf;
    } catch (e) {
      debugPrint('Error generating PDF: $e');
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
      // 🧾 نوع الطباعة الافتراضي (A4 أو حرارية 80mm) من إعدادات الطباعة
      // 🎨 طابعة حرارية مع تصميم إيصال مختار في «مصمم الفاتورة»
      final rollFormat = await InvoicePrintFormat.get() == '80mm';
      final rollDesigned = rollFormat ? await InvoiceLayoutStore.activeFor(PrintTarget.invoiceRoll.key) : null;
      final pdf = rollDesigned != null
          ? await generateInvoicePdf(target: PrintTarget.invoiceRoll.key)
          : rollFormat
          ? await RollInvoicePdf.build(
              items: invoiceItems,
              customerName: customerNameController.text,
              date: selectedDate,
              discount: discount,
              loadingFee: double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0,
              paid: double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0,
              paymentType: paymentType,
              invoiceNumber: invoiceToManage?.invoiceNumber ?? (invoiceToManage?.id == null ? null : '#${invoiceToManage!.id}'),
            )
          : await generateInvoicePdf();

      // 🖨️ تسجيل الطباعة (فاتورة محفوظة فقط؛ لا يوقف الطباعة إن فشل)
      if (widget.settlementForInvoice == null) {
        await PrintAudit.record(invoiceToManage?.id, kind: rollFormat ? 'roll' : 'a4');
      }

      // 🌐 على الويب: فتح نافذة طباعة المتصفح مباشرة وتجنب استدعاءات Platform
      if (kIsWeb) {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: 'فاتورة_${customerNameController.text}.pdf',
        );
        return;
      }

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
          if (!mounted) return;
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
            debugPrint('Error during print: $e');
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
      debugPrint('Error printing invoice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الطباعة: $e')),
        );
      }
    }
  }

// ============================================
// 4ب. 📨 إرسال الفاتورة لصاحبها عبر واتساب (الخادم)
// ============================================
  /// نفس ملف «مشاركة»، يُرسل مباشرة إلى رقم الفاتورة أو رقم العميل في سجل الديون.
  Future<void> sendInvoiceWhatsApp() => WaDocSender.send(context, () async {
        final pdf = await generateInvoicePdf();
        final bytes = await pdf.save();
        if (widget.settlementForInvoice == null) {
          await PrintAudit.record(invoiceToManage?.id, kind: 'share');
        }
        final name = customerNameController.text.trim();
        final safe = (name.isEmpty ? 'نقدية' : name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        return WaDoc(
          bytes: bytes,
          fileName: 'فاتورة_$safe.pdf',
          caption: 'فاتورة${invoiceToManage?.invoiceNumber == null ? '' : ' رقم ${invoiceToManage!.invoiceNumber}'}'
              '${name.isEmpty ? '' : ' — $name'}',
          customerId: invoiceToManage?.customerId,
          customerName: name,
          phone: customerPhoneController.text.trim(),
        );
      }, source: 'invoice');

// ============================================
// 4. دالة مشاركة الفاتورة (shareInvoice)
// ============================================
  Future<void> shareInvoice() async {
    try {
      final pdf = await generateInvoicePdf();
      if (widget.settlementForInvoice == null) {
        await PrintAudit.record(invoiceToManage?.id, kind: 'share');
      }
      // 🌐 الويب: مشاركة وتنزيل PDF مباشرة عبر المتصفح دون مجلدات مؤقتة
      if (kIsWeb) {
        final bytes = await pdf.save();
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'فاتورة_${customerNameController.text.isNotEmpty ? customerNameController.text : "نقدية"}.pdf',
        );
        return;
      }
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

