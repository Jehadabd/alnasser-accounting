// خدمة تصدير جميع الفواتير كملفات PDF منفصلة
import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../models/customer.dart';
import 'database_service.dart';
import 'settings_manager.dart';
import 'invoice_pdf_service.dart';
import 'logo_service.dart'; // 🖼️ Custom logo loading

class BulkInvoicePdfService {
  final DatabaseService _db = DatabaseService();

  /// تصدير جميع الفواتير كملفات PDF منفصلة
  /// يُرجع مسار المجلد الذي تم حفظ الملفات فيه
  Future<BulkExportResult> exportAllInvoicesToPdf({
    required Function(int current, int total, String invoiceName) onProgress,
  }) async {
    final results = BulkExportResult();
    
    try {
      // جلب جميع الفواتير مرتبة حسب التاريخ (الأحدث أولاً)
      final invoices = await _db.getAllInvoices();
      invoices.sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
      
      if (invoices.isEmpty) {
        results.success = false;
        results.errorMessage = 'لا توجد فواتير في النظام';
        return results;
      }

      results.totalCount = invoices.length;

      // جلب جميع المنتجات
      final allProducts = await _db.getAllProducts();

      // تحميل الخطوط
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
      final alnaserFont = pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
      
      // جلب إعدادات التطبيق
      final appSettings = await SettingsManager.getAppSettings();
      
      // تحميل اللوجو باستخدام خدمة اللوجو
      final logoImage = await LogoService.getLogoImage(appSettings: appSettings);

      // إنشاء مجلد للفواتير
      final now = DateTime.now();
      final folderName = 'فواتير_PDF_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      
      String basePath;
      if (Platform.isWindows) {
        basePath = '${Platform.environment['USERPROFILE']}/Documents/$folderName';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        basePath = '${dir.path}/$folderName';
      }
      
      final outputDir = Directory(basePath);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }
      
      results.outputPath = basePath;

      // إنشاء PDF لكل فاتورة
      for (var i = 0; i < invoices.length; i++) {
        final invoice = invoices[i];
        
        try {
          // تحديث التقدم
          onProgress(i + 1, invoices.length, invoice.customerName);

          // جلب أصناف الفاتورة
          final items = await _db.getInvoiceItems(invoice.id!);
          
          if (items.isEmpty) {
            results.skippedCount++;
            results.skippedInvoices.add('فاتورة #${invoice.formattedInvoiceNumber} - ${invoice.customerName} (بدون أصناف)');
            continue;
          }

          // حساب القيم المالية
          final itemsTotal = items.fold(0.0, (sum, item) => sum + item.itemTotal);
          final afterDiscount = (itemsTotal + invoice.loadingFee) - invoice.discount;
          final remaining = afterDiscount - invoice.amountPaidOnInvoice;
          
          // جلب الدين السابق والحالي
          double previousDebt = 0.0;
          double currentDebt = 0.0;
          if (invoice.customerId != null) {
            final customer = await _db.getCustomerById(invoice.customerId!);
            if (customer != null) {
              currentDebt = customer.currentTotalDebt;
              previousDebt = currentDebt - remaining;
            }
          }

          // إنشاء PDF
          final pdf = await InvoicePdfService.generateInvoicePdf(
            invoiceItems: items,
            allProducts: allProducts,
            customerName: invoice.customerName,
            customerAddress: invoice.customerAddress ?? '',
            customerPhone: invoice.customerPhone, // إضافة رقم الهاتف
            invoiceId: invoice.id!,
            selectedDate: invoice.invoiceDate,
            discount: invoice.discount,
            loadingFee: invoice.loadingFee,
            paid: invoice.amountPaidOnInvoice,
            paymentType: invoice.paymentType,
            invoiceToManage: invoice,
            previousDebt: previousDebt,
            currentDebt: currentDebt,
            afterDiscount: afterDiscount,
            remaining: remaining,
            font: font,
            alnaserFont: alnaserFont,
            logoImage: logoImage,
            createdAt: invoice.createdAt,
            appSettings: appSettings,
          );

          // حفظ الملف
          final safeCustomerName = _sanitizeFileName(invoice.customerName);
          final dateStr = '${invoice.invoiceDate.year}-${invoice.invoiceDate.month.toString().padLeft(2, '0')}-${invoice.invoiceDate.day.toString().padLeft(2, '0')}';
          final fileName = 'فاتورة_${invoice.formattedInvoiceNumber}_${safeCustomerName}_$dateStr.pdf';
          
          final file = File('$basePath/$fileName');
          await file.writeAsBytes(await pdf.save());
          
          results.exportedCount++;
        } catch (e) {
          results.failedCount++;
          results.failedInvoices.add('فاتورة #${invoice.formattedInvoiceNumber} - ${invoice.customerName}: $e');
        }
      }

      results.success = true;
    } catch (e) {
      results.success = false;
      results.errorMessage = e.toString();
    }

    return results;
  }

  /// تنظيف اسم الملف من الأحرف غير المسموحة
  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }
}

class BulkExportResult {
  bool success = false;
  String? errorMessage;
  String? outputPath;
  int totalCount = 0;
  int exportedCount = 0;
  int skippedCount = 0;
  int failedCount = 0;
  List<String> skippedInvoices = [];
  List<String> failedInvoices = [];

  String get summary {
    if (!success && errorMessage != null) {
      return 'فشل التصدير: $errorMessage';
    }
    
    final buffer = StringBuffer();
    buffer.writeln('تم تصدير $exportedCount فاتورة من أصل $totalCount');
    
    if (skippedCount > 0) {
      buffer.writeln('تم تخطي $skippedCount فاتورة (بدون أصناف)');
    }
    
    if (failedCount > 0) {
      buffer.writeln('فشل تصدير $failedCount فاتورة');
    }
    
    if (outputPath != null) {
      buffer.writeln('\nتم الحفظ في:\n$outputPath');
    }
    
    return buffer.toString();
  }
}
