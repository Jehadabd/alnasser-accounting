// خدمة تصدير الفواتير وإرسالها إلى Telegram
// تستخدم InvoicePdfService لضمان توحيد التصميم ودعم الأعمدة الديناميكية
import 'dart:io';
import 'dart:convert';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import 'database_service.dart';
import 'settings_manager.dart';
import 'telegram_backup_service.dart';
import 'invoice_pdf_service.dart'; // 🔄 استخدام InvoicePdfService الموحد
import 'logo_service.dart'; // 🖼️ Custom logo loading
import 'font_manager.dart'; // 🔡 Font management

class TelegramInvoiceExportService {
  final DatabaseService _db = DatabaseService();
  final TelegramBackupService _telegram = TelegramBackupService();

  /// تصدير الفواتير المُنشأة بعد تاريخ معين وإرسالها إلى Telegram
  Future<TelegramExportResult> exportAndSendNewInvoices({
    required DateTime afterDate,
    Function(int current, int total, String status)? onProgress,
  }) async {
    return _exportInvoicesInternal(afterDate: afterDate, onProgress: onProgress);
  }

  /// تصدير جميع الفواتير وإرسالها إلى Telegram
  Future<TelegramExportResult> exportAndSendAllInvoices({
    Function(int current, int total, String status)? onProgress,
  }) async {
    return _exportInvoicesInternal(onProgress: onProgress); // بدون تاريخ = الكل
  }

  /// دالة داخلية مشتركة للتصدير
  Future<TelegramExportResult> _exportInvoicesInternal({
    DateTime? afterDate,
    Function(int current, int total, String status)? onProgress,
  }) async {
    final result = TelegramExportResult();
    
    try {
      // التحقق من الإعدادات
      if (!await _telegram.isUserConfigured && !await _telegram.channelIdExists) {
        result.success = false;
        result.message = 'إعدادات Telegram غير مكتملة';
        return result;
      }

      onProgress?.call(0, 0, 'جاري تحضير الموارد...');
      print('📂 بدء عملية التصدير، المجلد المؤقت سيتم إنشاؤه...');
      
      final tempDir = await getTemporaryDirectory();
      final exportDir = Directory('${tempDir.path}/telegram_export_temp_${DateTime.now().millisecondsSinceEpoch}');
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true);
      }
      await exportDir.create();
      print('✅ تم إنشاء المجلد المؤقت: ${exportDir.path}');

      // تحميل الخطوط والإعدادات مرة واحدة
      print('📂 جاري تهيئة خطوط النظام...');
      await FontManager.loadArabicFonts();
      
      print('📂 جاري تحميل الخطوط للمعالجة...');
      // نضمن الحصول على خطوط غير فارغة باستخدام الاحتياطي
      final amiriData = await rootBundle.load("assets/fonts/Amiri-Regular.ttf");
      final fallbackFont = pw.Font.ttf(amiriData);
      
      final font = FontManager.getPdfFont('Amiri') ?? fallbackFont;
      final ptbData = await rootBundle.load("assets/fonts/PTBLDHAD.TTF");
      final alnaserFont = pw.Font.ttf(ptbData);
      print('✅ تم تهيئة الخطوط بنجاح (Amiri & PTBLDHAD)');
      
      final appSettings = await SettingsManager.getAppSettings();
      final logoImage = await LogoService.getLogoImage(appSettings: appSettings);
      final branchName = appSettings.branchName;

      // جلب الفواتير
      final db = await _db.database;
      List<Map<String, Object?>> invoicesData;
      
      if (afterDate != null) {
        final dateStr = afterDate.toIso8601String();
        print('🔍 جلب الفواتير بعد تاريخ: $dateStr');
        invoicesData = await db.query(
          'invoices',
          where: 'created_at > ? AND status = ?',
          whereArgs: [dateStr, 'محفوظة'],
          orderBy: 'id ASC',
        );
      } else {
        print('🔍 جلب جميع الفواتير المحفوظة...');
        invoicesData = await db.query(
          'invoices',
          where: 'status = ?',
          whereArgs: ['محفوظة'],
          orderBy: 'id ASC',
        );
      }
      print('📊 عدد الفواتير الموجودة: ${invoicesData.length}');

      if (invoicesData.isEmpty) {
        result.success = true;
        result.message = 'لا توجد فواتير لتصديرها';
        return result;
      }

      // جلب المنتجات لحساب الربح (مرة واحدة للأداء)
      final allProducts = await _db.getAllProducts();
      final productMap = {for (var p in allProducts) p.name: p};

      final totalInvoices = invoicesData.length;
      
      // إرسال رسالة بداية
      final startMsg = '📋 بدء إرسال $totalInvoices فاتورة\n'
          '🏪 $branchName\n'
          '📅 التاريخ: ${_formatDate(DateTime.now())}';
      await _telegram.sendMessage(startMsg);

      for (int i = 0; i < totalInvoices; i++) {
        final invMap = invoicesData[i];
        final invoice = Invoice.fromMap(invMap);
        print('📄 معالجة فاتورة #${invoice.formattedInvoiceNumber} لـ ${invoice.customerName}...');

        onProgress?.call(i + 1, totalInvoices, 'تصدير فاتورة #${invoice.formattedInvoiceNumber}...');
        
        try {
          // جلب عناصر الفاتورة
          final itemsData = await db.query(
            'invoice_items',
            where: 'invoice_id = ?',
            whereArgs: [invoice.id],
          );
          print('   📦 عدد العناصر في الفاتورة: ${itemsData.length}');
          final items = itemsData.map((e) => InvoiceItem.fromMap(e)).toList();
          
          if (items.isEmpty) {
            result.skippedCount++;
            continue;
          }

          // حساب القيم
          final itemsTotal = items.fold(0.0, (sum, item) => sum + item.itemTotal);
          final afterDiscount = (itemsTotal + invoice.loadingFee) - invoice.discount;
          final remaining = afterDiscount - invoice.amountPaidOnInvoice;
          
          // حساب الربح
          final invoiceProfit = _calculateInvoiceProfit(items, productMap, invoice.discount);
          
          double previousDebt = 0.0;
          double currentDebt = 0.0;
          
          String? customerPhone;
          String invoiceCustomerAddress = '';
          
          if (invoice.customerId != null) {
            final customer = await _db.getCustomerById(invoice.customerId!);
            if (customer != null) {
              currentDebt = customer.currentTotalDebt;
              previousDebt = currentDebt - remaining; // تقديري
              customerPhone = customer.phone;
              invoiceCustomerAddress = customer.address ?? '';
            }
          }

          // إنشاء PDF باستخدام InvoicePdfService الموحد
          final pdf = await InvoicePdfService.generateInvoicePdf(
            invoiceItems: items,
            allProducts: allProducts,
            customerName: invoice.customerName,
            customerAddress: invoiceCustomerAddress,
            customerPhone: customerPhone,
            invoiceId: invoice.id!,
            createdAt: invoice.invoiceDate, // استخدام تاريخ الفاتورة كـ createdAt
            selectedDate: invoice.invoiceDate,
            discount: invoice.discount,
            paid: invoice.amountPaidOnInvoice, // تم تغيير الاسم من amountPaid إلى paid
            loadingFee: invoice.loadingFee,
            paymentType: invoice.paymentType ?? 'نقدي',
            invoiceToManage: invoice,
            afterDiscount: afterDiscount,
            remaining: remaining,
            font: font,
            alnaserFont: alnaserFont,
            logoImage: logoImage,
            appSettings: appSettings,
            previousDebt: previousDebt,
            currentDebt: currentDebt,
          );

          // تسمية الملف بالشكل المطلوب: فاتورة_[ID]_[العميل]_مبلغ_[المبلغ]_ربح_[الربح].pdf
          final safeCustomerName = _sanitizeFileName(invoice.customerName);
          final safeBranch = _sanitizeFileName(branchName);
          final safeAmount = _formatNumber(afterDiscount).replaceAll('.', '_').replaceAll(',', '');
          final safeProfit = _formatNumber(invoiceProfit).replaceAll('.', '_').replaceAll(',', '');
          
          final fileName = 'فاتورة_${invoice.formattedInvoiceNumber}.pdf';
          
          final pdfFile = File('${exportDir.path}/$fileName');
          await pdfFile.writeAsBytes(await pdf.save());

          // إرسال إلى Telegram
          final caption = '🧾 فاتورة #${invoice.formattedInvoiceNumber}\n'
              '🏪 $branchName\n'
              '👤 ${invoice.customerName}\n'
              '💰 المبلغ: ${_formatNumber(afterDiscount)} د.ع\n'
              '📈 الربح: ${_formatNumber(invoiceProfit)} د.ع\n'
              '📅 ${_formatDate(invoice.invoiceDate)}';

          print('📤 جاري إرسال PDF للفاتورة #${invoice.formattedInvoiceNumber} إلى Telegram...');
          final sent = await _telegram.sendDocument(file: pdfFile, caption: caption);

          if (sent) {
            print('✅ نجح إرسال الفاتورة #${invoice.formattedInvoiceNumber}');
            result.sentCount++;
          } else {
            print('❌ فشل إرسال الفاتورة #${invoice.formattedInvoiceNumber}');
            result.failedCount++;
          }

          // تأخير لتجنب الحظر (مهم جداً عند إرسال كميات كبيرة)
          await Future.delayed(const Duration(milliseconds: 3500)); // 3.5 ثانية آمنة
          
        } catch (e, stack) {
          result.failedCount++;
          print('❌ خطأ في معالجة الفاتورة #${invoice.id}: $e');
          print('Stack trace: $stack');
        }
      }

      // تنظيف
      try {
        await exportDir.delete(recursive: true);
      } catch (_) {}

      // رسالة الختام
      final endMsg = '✅ اكتمل النقل\n'
          '📊 الإحصائيات:\n'
          '✅ تم إرسال: ${result.sentCount}\n'
          '❌ فشل: ${result.failedCount}\n'
          '⏭️ تم تخطي: ${result.skippedCount}\n'
          '📦 الإجمالي: $totalInvoices';
      await _telegram.sendMessage(endMsg);

      result.success = true;
      result.message = 'تم إرسال ${result.sentCount} فاتورة';
      
    } catch (e, stack) {
      result.success = false;
      result.message = 'خطأ عام: $e';
      print('🔥 خطأ فادح في عملية التصدير: $e');
      print('Stack trace: $stack');
    }

    return result;
  }

  String _formatNumber(num value) {
    final formatter = NumberFormat('#,##0.##', 'en_US');
    return formatter.format(value);
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  String _sanitizeFileName(String name) {
    // السماح بالحروف العربية والإنجليزية والأرقام، والباقي استبداله بـ underscore
    // \u0600-\u06FF تغطي النطاق العربي الأساسي
    return name
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF0-9\s]+'), '_') // استبدال الرموز الخاصة
        .replaceAll(RegExp(r'\s+'), '_') // استبدال المسافات
        .trim();
  }

  /// حساب إجمالي ربح الفاتورة
  double _calculateInvoiceProfit(List<InvoiceItem> items, Map<String, Product> productMap, double discount) {
    double totalProfit = 0.0;
    
    for (var item in items) {
      final double sellingPrice = item.appliedPrice;
      final double? acp = item.actualCostPrice;
      final double itemBaseCost = item.costPrice ?? 0.0;
      
      final String saleType = item.saleType ?? '';
      final double qi = item.quantityIndividual ?? 0.0;
      final double ql = item.quantityLargeUnit ?? 0.0;
      final double uilu = item.unitsInLargeUnit ?? 0.0;
      
      // جلب بيانات المنتج
      final Product? product = productMap[item.productName];
      final String productUnit = product?.unit ?? '';
      final double lengthPerUnit = product?.lengthPerUnit ?? 1.0;
      final double productBaseCost = product?.costPrice ?? 0.0;
      final Map<String, double> unitCosts = product?.getUnitCostsMap() ?? {};
      
      final bool soldAsLargeUnit = ql > 0;
      final double saleUnitsCount = soldAsLargeUnit ? ql : qi;
      
      double costPerSaleUnit;
      
      if (acp != null && acp > 0) {
        costPerSaleUnit = acp;
      } else if (soldAsLargeUnit) {
        if (unitCosts.containsKey(saleType)) {
          costPerSaleUnit = unitCosts[saleType]!;
        } else if (productUnit == 'meter' && saleType == 'لفة') {
          costPerSaleUnit = productBaseCost * lengthPerUnit;
        } else if (uilu > 0) {
          costPerSaleUnit = productBaseCost * uilu;
        } else {
          costPerSaleUnit = _calculateCostFromHierarchy(
            productCost: productBaseCost,
            saleType: saleType,
            unitHierarchyJson: product?.unitHierarchy,
          );
        }
      } else {
        costPerSaleUnit = itemBaseCost > 0 ? itemBaseCost : productBaseCost;
      }
      
      if (costPerSaleUnit <= 0 && sellingPrice > 0) {
        costPerSaleUnit = sellingPrice * 0.9; // 10% ربح افتراضي
      }
      
      final double lineAmount = sellingPrice * saleUnitsCount;
      final double lineCostTotal = costPerSaleUnit * saleUnitsCount;
      
      totalProfit += (lineAmount - lineCostTotal);
    }
    
    return totalProfit - discount;
  }

  double _calculateCostFromHierarchy({
    required double productCost,
    required String saleType,
    required String? unitHierarchyJson,
  }) {
    if (unitHierarchyJson == null || unitHierarchyJson.trim().isEmpty) {
      return productCost;
    }
    
    try {
      final List<dynamic> hierarchy = json.decode(unitHierarchyJson.replaceAll("'", '"'));
      double multiplier = 1.0;
      
      for (final level in hierarchy) {
        final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
        final double qty = (level['quantity'] is num)
            ? (level['quantity'] as num).toDouble()
            : double.tryParse(level['quantity'].toString()) ?? 1.0;
        multiplier *= qty;
        
        if (unitName == saleType) {
          return productCost * multiplier;
        }
      }
      
      return productCost;
    } catch (e) {
      return productCost;
    }
  }
}

class TelegramExportResult {
  bool success = false;
  String message = '';
  int totalCount = 0;
  int sentCount = 0;
  int failedCount = 0;
  int skippedCount = 0;
}
