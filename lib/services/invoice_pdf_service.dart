// services/invoice_pdf_service.dart
import '../erp/arabic_words.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'dart:convert';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/customer.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/models/font_settings.dart';
import 'package:alnaser/services/font_manager.dart';
import 'package:alnaser/services/pdf_header.dart';
import 'package:alnaser/utils/arabic_shaper.dart';
import 'database_service.dart';

class InvoicePdfService {
  static Future<pw.Document> generateInvoicePdf({
    required List<InvoiceItem> invoiceItems,
    required List<Product> allProducts,
    required String customerName,
    required String customerAddress,
    String? customerPhone, // إضافة رقم الهاتف
    required int invoiceId,
    required DateTime selectedDate,
    required double discount,
    required double loadingFee,
    required double paid,
    required String paymentType,
    required Invoice? invoiceToManage,
    required double previousDebt,
    required double currentDebt,
    required double afterDiscount,
    required double remaining,
    required pw.Font font,
    required pw.Font alnaserFont,
    required pw.MemoryImage? logoImage,
    required DateTime? createdAt,
    required AppSettings appSettings,
  }) async {
    final pdf = pw.Document();
    const itemsPerPage = 20;
    final totalPages = (invoiceItems.length / itemsPerPage).ceil();
    
    // تنسيق التاريخ والوقت مدمجين: dd-MM-yyyy HH:mm
    final dateTime = createdAt ?? DateTime.now();
    final formattedDateTime = '${selectedDate.day.toString().padLeft(2, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    
    // تقليص النصوص للحد الأقصى المسموح
    String truncate(String text, int maxLen) {
      if (text.length <= maxLen) return text;
      return text.substring(0, maxLen - 2) + '..';
    }
    
    for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final start = pageIndex * itemsPerPage;
      final end = (start + itemsPerPage) > invoiceItems.length
          ? invoiceItems.length
          : start + itemsPerPage;
      final pageItems = invoiceItems.sublist(start, end);
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
                  // استخدام الهيدر الموحد من pdf_header.dart
                  buildPdfHeader(font, alnaserFont, logoImage, appSettings: appSettings),
                  // صف معلومات الفاتورة مع مساحات محددة (الهيدر الجديد)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Container(
                        width: 100, // تم تقليل المساحة بمقدار 10
                        child: pw.Text('السيد: $customerName',
                            style: pw.TextStyle(font: font, fontSize: 12),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip),
                      ),
                      pw.Container(
                        width: 135,
                        child: pw.Text(
                            'العنوان: ${customerAddress.isNotEmpty ? customerAddress : ' ______'}',
                            style: pw.TextStyle(font: font, fontSize: 11),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip),
                      ),
                      pw.Container(
                        width: 85,
                        child: pw.Text('الهاتف: ${customerPhone?.isNotEmpty == true ? customerPhone : '___________'}',
                            style: pw.TextStyle(font: font, fontSize: 11),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip),
                      ),
                      pw.Container(
                        width: 80,
                        child: pw.Text('رقم الفاتورة: ${invoiceToManage?.formattedInvoiceNumber ?? invoiceId}',
                            style: pw.TextStyle(font: font, fontSize: 10),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip),
                      ),
                      pw.Container(
                        width: 150, // مساحة إضافية لكلمة التاريخ
                        padding: const pw.EdgeInsets.only(right: 5), 
                        child: pw.Directionality(
                          textDirection: pw.TextDirection.ltr,
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            mainAxisSize: pw.MainAxisSize.max,
                            children: [
                              pw.Text(
                                invoiceToManage?.formattedInvoiceDate ?? formattedDateTime,
                                style: pw.TextStyle(font: font, fontSize: 11),
                              ),
                              pw.SizedBox(width: 4),
                              pw.Directionality(
                                textDirection: pw.TextDirection.rtl,
                                child: pw.Text(
                                  'التاريخ:',
                                  style: pw.TextStyle(font: font, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.Divider(height: 5, thickness: 0.5),
                  // جدول الفاتورة الديناميكي: يستخدم إعدادات الأعمدة من InvoiceDesignSettings
                  _buildDynamicInvoiceTable(
                    pageItems: pageItems,
                    pageIndex: pageIndex,
                    itemsPerPage: itemsPerPage,
                    allProducts: allProducts,
                    font: font,
                    appSettings: appSettings,
                  ),
                  pw.Divider(height: 4, thickness: 0.4),
                  if (pageIndex == totalPages - 1) ...[
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            summaryRow('الاجمالي قبل الخصم:', currentTotalAmount(invoiceItems) + loadingFee, font, fontSettings: appSettings.fontSettings.totalBeforeDiscount),
                            pw.SizedBox(width: 10),
                            summaryRow('أجور التحميل:', loadingFee, font, color: PdfColor.fromInt(appSettings.loadingFeesColor), fontSettings: appSettings.fontSettings.shippingFees),
                            pw.SizedBox(width: 10),
                            summaryRow('الخصم:', discount, font, fontSettings: appSettings.fontSettings.discount),
                            pw.SizedBox(width: 10),
                            summaryRow('الاجمالي بعد الخصم:', afterDiscount, font, fontSettings: appSettings.fontSettings.totalAfterDiscount),
                            pw.SizedBox(width: 10),
                            summaryRow('المبلغ المدفوع:', paid, font, color: PdfColor.fromInt(appSettings.paidAmountColor), fontSettings: appSettings.fontSettings.paidAmount),
                          ],
                        ),
                        pw.SizedBox(height: 6),
                        if ((invoiceToManage?.status == 'محفوظة') && !(invoiceToManage?.isLocked ?? false)) ...[
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              summaryRow('المبلغ المتبقي:', remaining, font, color: PdfColor.fromInt(appSettings.remainingAmountColor), fontSettings: appSettings.fontSettings.remainingAmount),
                              pw.SizedBox(width: 10),
                              summaryRow('الدين السابق:', previousDebt, font, fontSettings: appSettings.fontSettings.previousDebt),
                              pw.SizedBox(width: 10),
                              summaryRow('المبلغ المطلوب الحالي:', currentDebt, font, fontSettings: appSettings.fontSettings.currentRequiredAmount),
                            ],
                          ),
                        ],
                      ],
                    ),
                    // 🔤 المبلغ كتابةً (التفقيط)
                    pw.SizedBox(height: 4),
                    pw.Directionality(
                      textDirection: pw.TextDirection.rtl,
                      child: pw.Text(ArabicWords.money(afterDiscount.toDouble()),
                          style: pw.TextStyle(font: font, fontSize: 10)),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Center(
                        child: pw.Text('شكراً لتعاملكم معنا',
                            style: pw.TextStyle(font: font, fontSize: 11))),
                  ],
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      'صفحة ${pageIndex + 1} من $totalPages',
                      style: pw.TextStyle(font: font, fontSize: 11),
                    ),
                  ),
                    ],
                  ),
                  // طبقة أمامية: اسم الشركة نصف شفاف (Watermark)
                  pw.Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: pw.Container(
                      alignment: pw.Alignment.topLeft,
                      padding: const pw.EdgeInsets.only(top: 130, left: 5),
                      child: pw.Transform.rotate(
                        angle: 0.6,
                        child: pw.Opacity(
                          opacity: 0.20,
                          child: pw.Text(
                            appSettings.invoiceDesign.companyName, // استخدام اسم الشركة من الإعدادات
                            style: pw.TextStyle(
                              font: alnaserFont,
                              fontFallback: [font],
                              fontSize: 200,
                              color: PdfColors.green,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textDirection: pw.TextDirection.rtl,
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
    }
    return pdf;
  }

  // وثيقة تجهيز بدون أسعار أو مبالغ (تسلسل، ID، التفاصيل، العدد، نوع البيع فقط)
  // الهيدر مثل الفاتورة العادية تماماً باستخدام buildPdfHeader
  static Future<pw.Document> generatePickingListPdf({
    required List<InvoiceItem> invoiceItems,
    required List<Product> allProducts,
    required String customerName,
    required int invoiceId,
    required DateTime selectedDate,
    required pw.Font font,
    required pw.Font alnaserFont,
    required pw.MemoryImage? logoImage,
    required AppSettings appSettings,
  }) async {
    final pdf = pw.Document();
    const itemsPerPage = 20; // عدد أقل لأن الهيدر أكبر
    final totalPages = (invoiceItems.length / itemsPerPage).ceil().clamp(1, 9999);
    for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final start = pageIndex * itemsPerPage;
      final end = (start + itemsPerPage) > invoiceItems.length
          ? invoiceItems.length
          : start + itemsPerPage;
      final pageItems = invoiceItems.sublist(start, end);
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
                      // ═══════════════════════════════════════════════════════════════
                      // استخدام buildPdfHeader للهيدر الموحد مع الفاتورة العادية
                      // ═══════════════════════════════════════════════════════════════
                      buildPdfHeader(font, alnaserFont, logoImage, appSettings: appSettings),
                      // عنوان قائمة التجهيز
                      pw.Center(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(width: 1),
                            borderRadius: pw.BorderRadius.circular(5),
                          ),
                          child: pw.Text(
                            'قائمة تجهيز - فاتورة #$invoiceId',
                            style: pw.TextStyle(
                              font: alnaserFont,
                              fontFallback: [font],
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textDirection: pw.TextDirection.rtl,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      // معلومات العميل والتاريخ
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('السيد: $customerName',
                              style: pw.TextStyle(font: font, fontFallback: [font], fontSize: 12)),
                          pw.Text(
                            'التاريخ: ${selectedDate.year}/${selectedDate.month}/${selectedDate.day}',
                            style: pw.TextStyle(font: font, fontFallback: [font], fontSize: 11),
                          ),
                        ],
                      ),
                      pw.Divider(height: 5, thickness: 0.5),
                      // ═══════════════════════════════════════════════════════════════
                      // جدول عناصر التجهيز
                      // ═══════════════════════════════════════════════════════════════
                      pw.Table(
                        border: pw.TableBorder.all(width: 0.2),
                        columnWidths: const {
                          0: pw.FixedColumnWidth(70),  // التأشيرة (أقصى اليسار)
                          1: pw.FixedColumnWidth(70),  // العدد
                          2: pw.FixedColumnWidth(70),  // نوع البيع
                          3: pw.FlexColumnWidth(1.2),  // التفاصيل
                          4: pw.FixedColumnWidth(60),  // ID
                          5: pw.FixedColumnWidth(22),  // ت (أقصى اليمين)
                        },
                        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                        children: [
                          pw.TableRow(children: [
                            headerCell('التأشيرة', font),
                            headerCell('العدد', font, color: PdfColor.fromInt(appSettings.itemQuantityColor), fontSettings: appSettings.fontSettings.quantity),
                            headerCell('نوع البيع', font),
                            headerCell('التفاصيل', font, color: PdfColor.fromInt(appSettings.itemDetailsColor), fontSettings: appSettings.fontSettings.productDetails),
                            headerCell('ID', font, color: PdfColor.fromInt(appSettings.itemSerialColor), fontSettings: appSettings.fontSettings.productId),
                            headerCell('ت', font, color: PdfColor.fromInt(appSettings.itemSerialColor), fontSettings: appSettings.fontSettings.serialNumber),
                          ]),
                          ...pageItems.asMap().entries.map((entry) {
                            final idx = entry.key + (pageIndex * itemsPerPage);
                            final item = entry.value;
                            final quantity = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0);
                            Product? product;
                            try {
                              product = allProducts.firstWhere((p) => p.name == item.productName);
                            } catch (_) {}
                            return pw.TableRow(children: [
                              dataCell('', font), // التأشيرة
                              dataCell('${formatNumber(quantity, forceDecimal: true)}', font, color: PdfColor.fromInt(appSettings.itemQuantityColor), fontSettings: appSettings.fontSettings.quantity),
                              dataCell(item.saleType ?? '', font),
                              dataCell(item.productName, font, align: pw.TextAlign.right, color: PdfColor.fromInt(appSettings.itemDetailsColor), fontSettings: appSettings.fontSettings.productDetails),
                              dataCell(formatProductId(product?.id), font, color: PdfColor.fromInt(appSettings.itemSerialColor), fontSettings: appSettings.fontSettings.productId),
                              dataCell('${idx + 1}', font, color: PdfColor.fromInt(appSettings.itemSerialColor), fontSettings: appSettings.fontSettings.serialNumber),
                            ]);
                          }).toList(),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Align(
                        alignment: pw.Alignment.center,
                        child: pw.Text('صفحة ${pageIndex + 1} من $totalPages',
                            style: pw.TextStyle(font: font, fontFallback: [font], fontSize: 11)),
                      ),
                    ],
                  ),
                  // العلامة المائية
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
                          opacity: 0.1,
                          child: pw.Text(
                            appSettings.invoiceDesign.companyName,
                            style: pw.TextStyle(
                              font: alnaserFont,
                              fontFallback: [font],
                              fontSize: 200, // Reduced slightly to accommodate longer names potentially
                              color: PdfColors.grey400,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textDirection: pw.TextDirection.rtl,
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
    }
    return pdf;
  }

  static pw.Widget headerCell(String text, pw.Font font, {PdfColor? color, FontElementSettings? fontSettings}) {
    // استخدام الخط العربي الأساسي (Amiri) دائماً لضمان عرض النص العربي بشكل صحيح
    // تطبيق الوزن فقط من الإعدادات
    pw.FontWeight? customWeight;
    
    if (fontSettings != null) {
      customWeight = FontManager.getPdfFontWeight(fontSettings.fontWeight);
    }
    
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font, // استخدام الخط العربي الأساسي دائماً
              fontSize: 13, 
              fontWeight: customWeight ?? pw.FontWeight.bold, 
              color: color ?? PdfColors.black),
          textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget dataCell(String text, pw.Font font,
      {pw.TextAlign align = pw.TextAlign.center, PdfColor? color, FontElementSettings? fontSettings}) {
    // استخدام الخط العربي الأساسي (Amiri) دائماً لضمان عرض النص العربي بشكل صحيح
    // تطبيق الوزن فقط من الإعدادات
    pw.FontWeight? customWeight;
    
    if (fontSettings != null) {
      customWeight = FontManager.getPdfFontWeight(fontSettings.fontWeight);
    }
    
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font, // استخدام الخط العربي الأساسي دائماً
              fontSize: 13, 
              fontWeight: customWeight ?? pw.FontWeight.bold, 
              color: color ?? PdfColors.black),
          textAlign: align),
    );
  }

  static String formatProductId(int? id) {
    // عرض المعرّف كما هو بدون حشو أصفار أو الهاشتاق
    if (id == null) return '';
    return id.toString();
  }

  static pw.Widget summaryRow(String label, num value, pw.Font font, {PdfColor? color, FontElementSettings? fontSettings}) {
    // تطبيق إعدادات الخط إذا كانت متوفرة
    pw.Font? customFont;
    pw.FontWeight? customWeight;
    
    if (fontSettings != null) {
      customFont = FontManager.getPdfFont(fontSettings.fontFamily);
      customWeight = FontManager.getPdfFontWeight(fontSettings.fontWeight);
    }
    
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: pw.TextStyle(font: customFont ?? font, fontSize: 11, color: color)),
          pw.SizedBox(width: 5),
          pw.Text(formatNumber(value, forceDecimal: true),
              style: pw.TextStyle(
                  font: customFont ?? font, 
                  fontSize: 13, 
                  fontWeight: customWeight ?? pw.FontWeight.bold, 
                  color: color)),
        ],
      ),
    );
  }

  static String buildUnitConversionStringForPdf(InvoiceItem item, Product? product) {
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

  static String formatNumber(num value, {bool forceDecimal = false}) {
    if (forceDecimal) {
      return value % 1 == 0 ? value.toInt().toString() : value.toString();
    }
    return value.toInt().toString();
  }

  static double currentTotalAmount(List<InvoiceItem> invoiceItems) {
    return invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
  }

  static Future<String?> getSavePath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);
    if (await file.exists()) {
      final result = await showDialog<bool>(
        context: navigatorKey.currentContext!,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('تأكيد الحفظ'),
            content: Text('الملف "$fileName" موجود بالفعل. هل تريد استبداله؟'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('لا'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('نعم'),
              ),
            ],
          );
        },
      );
      if (result == true) {
        await file.delete();
        return path;
      }
      return null;
    }
    return path;
  }

  static final navigatorKey = GlobalKey<NavigatorState>();

  /// بناء جدول الفاتورة الديناميكي بناءً على إعدادات الأعمدة
  static pw.Widget _buildDynamicInvoiceTable({
    required List<InvoiceItem> pageItems,
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
      return pw.SizedBox(); // لا يظهر شيء
    }

    // بناء خريطة عرض الأعمدة - ترتيب معكوس لـ RTL
    final columnWidths = <int, pw.TableColumnWidth>{};
    for (int i = 0; i < visibleColumns.length; i++) {
      final col = visibleColumns[visibleColumns.length - 1 - i]; // عكس الترتيب لـ RTL
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
      headerCells.add(_getHeaderCellForColumn(col.id, col.label, font, appSettings));
    }

    // بناء صفوف البيانات
    final dataRows = pageItems.asMap().entries.map((entry) {
      final index = entry.key + (pageIndex * itemsPerPage);
      final item = entry.value;
      
      // البحث عن المنتج
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
        rowCells.add(_getDataCellForColumn(col.id, index, item, product, font, appSettings));
      }
      
      return pw.TableRow(children: rowCells);
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
  static pw.Widget _getHeaderCellForColumn(String columnId, String label, pw.Font font, AppSettings appSettings) {
    // تشكيل النص العربي للرؤوس
    final shapedLabel = ArabicShaper.shape(label);
    
    switch (columnId) {
      case 'serial':
        return headerCell(shapedLabel, font, color: PdfColor.fromInt(appSettings.itemSerialColor), fontSettings: appSettings.fontSettings.serialNumber);
      case 'productId':
        return headerCell(shapedLabel, font, color: PdfColor.fromInt(appSettings.itemSerialColor), fontSettings: appSettings.fontSettings.productId);
      case 'details':
        return headerCell(shapedLabel, font, color: PdfColor.fromInt(appSettings.itemDetailsColor), fontSettings: appSettings.fontSettings.productDetails);
      case 'quantity':
        return headerCell(shapedLabel, font, color: PdfColor.fromInt(appSettings.itemQuantityColor), fontSettings: appSettings.fontSettings.quantity);
      case 'unitsCount':
        return headerCell(shapedLabel, font, fontSettings: appSettings.fontSettings.unitsCount);
      case 'price':
        return headerCell(shapedLabel, font, color: PdfColor.fromInt(appSettings.itemPriceColor), fontSettings: appSettings.fontSettings.price);
      case 'amount':
        return headerCell(shapedLabel, font, color: PdfColor.fromInt(appSettings.itemTotalColor), fontSettings: appSettings.fontSettings.amount);
      case 'weight':
        return headerCell(shapedLabel, font, fontSettings: appSettings.fontSettings.quantity);
      case 'expiry':
        return headerCell(shapedLabel, font, fontSettings: appSettings.fontSettings.quantity);
      default:
        return headerCell(shapedLabel, font);
    }
  }

  /// الحصول على خلية البيانات للعمود المحدد
  static pw.Widget _getDataCellForColumn(String columnId, int index, InvoiceItem item, Product? product, pw.Font font, AppSettings appSettings) {
    final quantity = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0);
    
    switch (columnId) {
      case 'serial':
        return dataCell('${index + 1}', font, color: PdfColor.fromInt(appSettings.itemSerialColor), fontSettings: appSettings.fontSettings.serialNumber);
      case 'productId':
        return dataCell(formatProductId(product?.id), font, color: PdfColor.fromInt(appSettings.itemSerialColor), fontSettings: appSettings.fontSettings.productId);
      case 'details':
        return dataCell(ArabicShaper.shape(item.productName), font, align: pw.TextAlign.right, color: PdfColor.fromInt(appSettings.itemDetailsColor), fontSettings: appSettings.fontSettings.productDetails);
      case 'quantity':
        return dataCell(ArabicShaper.shape('${formatNumber(quantity, forceDecimal: true)} ${item.saleType ?? ''}'), font, color: PdfColor.fromInt(appSettings.itemQuantityColor), fontSettings: appSettings.fontSettings.quantity);
      case 'unitsCount':
        return dataCell(ArabicShaper.shape(buildUnitConversionStringForPdf(item, product)), font, fontSettings: appSettings.fontSettings.unitsCount);
      case 'price':
        return dataCell(formatNumber(item.appliedPrice, forceDecimal: true), font, color: PdfColor.fromInt(appSettings.itemPriceColor), fontSettings: appSettings.fontSettings.price);
      case 'amount':
        return dataCell(formatNumber(item.itemTotal, forceDecimal: true), font, color: PdfColor.fromInt(appSettings.itemTotalColor), fontSettings: appSettings.fontSettings.amount);
      case 'weight':
        final weight = product?.baseWeight;
        if (weight != null && weight > 0) {
          final totalWeight = weight * quantity;
          return dataCell(ArabicShaper.shape('${formatNumber(totalWeight, forceDecimal: true)} كغ'), font, fontSettings: appSettings.fontSettings.quantity);
        }
        return dataCell('', font);
      case 'expiry':
        if (product?.hasExpiry == true) {
          return dataCell(ArabicShaper.shape('له'), font, fontSettings: appSettings.fontSettings.quantity);
        }
        return dataCell('', font);
      default:
        return dataCell('', font);
    }
  }
}
