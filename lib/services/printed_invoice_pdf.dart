// lib/services/printed_invoice_pdf.dart
//
// 🖨️ التصميم الأصلي لفاتورة البيع (A4) — المصدر الوحيد للشكل المطبوع.
// تستعمله الطباعة من شاشة الفاتورة، ونسخة تيليجرام، فيخرج الملفان متطابقين في الشكل.
// (نُقل كما هو من invoice_actions.dart؛ الأرقام تُحسب عند المستدعي وتُمرَّر هنا.)

import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/app_settings.dart';
import '../models/invoice.dart';
import '../models/invoice_adjustment.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import 'invoice_pdf_service.dart';
import 'pdf_header.dart';
import 'product_codes.dart';
import '../models/invoice_design_settings.dart' show InvoiceColumnConfig; // 🛡️ أعمدة الضمان
import '../erp/warranty/item_warranty.dart'; // 🛡️ ضمان السطر
import 'invoice_extras_pdf.dart'; // ⚖️🛡️ وزن الفاتورة وشروط الضمان

String _pid5(int? id) {
  if (id == null) return '-----';
  return id.toString().padLeft(5, '0');
}

class PrintedInvoicePdf {
  PrintedInvoicePdf._();

  static String formatNumber(num value, {bool forceDecimal = false}) {
    final formatter = NumberFormat('#,##0.##', 'en_US');
    return formatter.format(value);
  }

  static pw.Widget _headerCell(String text, pw.Font font, {PdfColor? color}) {
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

  static pw.Widget _dataCell(String text, pw.Font font,
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

  static pw.Widget _summaryRow(String label, num value, pw.Font font,
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
  static pw.Widget _buildInvoiceInfoRow({
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
      return '${text.substring(0, maxLen - 2)}..';
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
  static pw.Widget _buildDynamicTableForPdf({
    required List<Map<String, dynamic>> pageRows,
    bool anyLineDiscount = false,
    bool anyWarranty = false,
    required int pageIndex,
    required int itemsPerPage,
    required List<Product> allProducts,
    required pw.Font font,
    required AppSettings appSettings,
  }) {
    // الحصول على الأعمدة المرئية مرتبة
    // 🏷️ «السعر قبل الخصم» و«الخصم» فقط إن كان في الفاتورة صنف مخصوم أو هدية
    // 🛡️ وأعمدة الضمان فقط إن كان فيها سطر له ضمان
    final visibleColumns = appSettings.invoiceDesign.visibleColumns
        .where((c) => anyLineDiscount || (c.id != 'discount' && c.id != 'priceBeforeDiscount'))
        .where((c) => anyWarranty || !InvoiceColumnConfig.isWarranty(c.id))
        .toList();
    
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
  static pw.Widget _getHeaderCellForDynamic(String columnId, String label, pw.Font font, AppSettings appSettings) {
    switch (columnId) {
      case 'serial':
        return _headerCell(label, font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'productId':
      case 'itemCode':
      case 'barcode':
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
      case 'priceBeforeDiscount':
      case 'discount':
        return _headerCell(label, font);
      case 'weight':
        return _headerCell(label, font);
      case 'expiry':
        return _headerCell(label, font);
      default:
        return _headerCell(label, font);
    }
  }

  /// الحصول على خلية البيانات للعمود المحدد (للعناصر العادية)
  static pw.Widget _getDataCellForDynamic(String columnId, int index, InvoiceItem item, Product? product, pw.Font font, AppSettings appSettings) {
    final quantity = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0);
    
    switch (columnId) {
      case 'serial':
        return _dataCell('${index + 1}', font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'productId':
        return _dataCell(_pid5(product?.id), font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'itemCode':
        return _dataCell(ProductCodes.codeOf(product?.id) ?? '', font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'barcode':
        return _dataCell((product?.barcode ?? '').trim(), font, color: PdfColor.fromInt(appSettings.itemSerialColor));
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
      case 'priceBeforeDiscount':
        return _dataCell(
            item.hasLineDiscount ? formatNumber(item.priceBeforeDiscount ?? item.appliedPrice, forceDecimal: true) : '',
            font);
      case 'discount':
        return _dataCell(item.discountLabel, font);
      case 'weight':
        final weight = product?.baseWeight;
        if (weight != null && weight > 0) {
          // ⚖️ بالوحدة الأساسية: الكرتون × عدد قطعه (كان يضرب في عدد الكراتين)
          final totalWeight = weight * item.baseQuantity;
          return _dataCell('${formatNumber(totalWeight, forceDecimal: true)} كغ', font);
        }
        return _dataCell('', font);
      case 'expiry':
        // 📅 تاريخ الانتهاء نفسه (كان يطبع «له»)
        if (product?.hasExpiry == true) {
          final t = InvoiceItem.expiryText(product?.expiryDate);
          return _dataCell(t.isEmpty ? 'له' : t, font);
        }
        return _dataCell('', font);
      case ItemWarranty.colPeriod:
      case ItemWarranty.colStart:
      case ItemWarranty.colEnd:
        // 🛡️ الضمان المثبَّت على السطر عند البيع
        return _dataCell(
            ItemWarranty.cellText(columnId,
                    spec: item.warrantySpec, start: item.warrantyStart, end: item.warrantyEnd) ??
                '',
            font);
      default:
        return _dataCell('', font);
    }
  }

  /// الحصول على خلية البيانات للتسويات (adjustments)
  static pw.Widget _getAdjustmentCellForDynamic(String columnId, int index, InvoiceAdjustment a, Product? product, pw.Font font, AppSettings appSettings) {
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
        return _dataCell(_pid5(product?.id), font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'itemCode':
        return _dataCell(ProductCodes.codeOf(product?.id) ?? '', font, color: PdfColor.fromInt(appSettings.itemSerialColor));
      case 'barcode':
        return _dataCell((product?.barcode ?? '').trim(), font, color: PdfColor.fromInt(appSettings.itemSerialColor));
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
          final per = a.unitsInLargeUnit ?? 0;
          final totalWeight = weight * (per > 0 ? qty * per : qty); // ⚖️ بالوحدة الأساسية
          return _dataCell('${formatNumber(totalWeight, forceDecimal: true)} كغ', font);
        }
        return _dataCell('', font);
      case 'expiry':
        // 📅 تاريخ الانتهاء نفسه (كان يطبع «له»)
        if (product?.hasExpiry == true) {
          final t = InvoiceItem.expiryText(product?.expiryDate);
          return _dataCell(t.isEmpty ? 'له' : t, font);
        }
        return _dataCell('', font);
      default:
        return _dataCell('', font);
    }
  }

  /// يضيف صفحات الفاتورة بالتصميم الأصلي إلى [pdf].
  static Future<void> addOriginalPages(
    pw.Document pdf, {
    required pw.Font font,
    required pw.Font alnaserFont,
    required pw.MemoryImage? logoImage,
    required AppSettings appSettings,
    required List<Map<String, dynamic>> combinedRows,
    required List<InvoiceItem> itemsForPdf,
    required List<Product> allProducts,
    required bool showSettlementSections,
    required List<InvoiceAdjustment> itemAdditionsForSection,
    required List<InvoiceAdjustment> itemCreditsForSection,
    required List<InvoiceAdjustment> amountOnlyAdjs,
    required String invoiceDisplayNumber,
    required String customerName,
    required String customerAddress,
    required String customerPhone,
    required DateTime selectedDate,
    required Invoice? invoiceToManage,
    required double preDiscountTotal,
    required double discount,
    required double afterDiscount,
    required double loadingFee,
    required double displayedPaidForSettlementsCase,
    required double remainingForPdf,
    required double currentDebtForPdf,
  }) async {
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
            margin: const pw.EdgeInsets.only(top: 0, bottom: 2, left: 10, right: 10),
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
                          customerName: customerName,
                          customerAddress: customerAddress,
                          customerPhone: customerPhone,
                          invoiceDisplayNumber: invoiceDisplayNumber,
                          selectedDate: selectedDate,
                          createdAt: invoiceToManage?.createdAt,
                        ),
                        pw.Divider(height: 5, thickness: 0.5),
                        // جدول الفاتورة الديناميكي بناءً على إعدادات الأعمدة
                        _buildDynamicTableForPdf(
                          pageRows: pageRows,
                          anyLineDiscount: itemsForPdf.any((it) => it.hasLineDiscount), // 🏷️
                          anyWarranty: itemsForPdf.any((it) => it.hasWarranty), // 🛡️
                          pageIndex: pageIndex,
                          itemsPerPage: itemsPerPage,
                          allProducts: allProducts,
                          font: font,
                          appSettings: appSettings,
                        ),
                        pw.Divider(height: 4, thickness: 0.4),
                        // ⚖️🛡️ وزن الفاتورة وشروط الضمان تحت آخر بند (الصفحة الأخيرة)
                        if (isLast) ...InvoiceExtrasPdf.block(itemsForPdf, allProducts, font),
                        if (isLast && !deferSummary) ...[
                          if (invoiceToManage != null &&
                              invoiceToManage.id != null &&
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
          margin: const pw.EdgeInsets.only(top: 10, bottom: 10, left: 10, right: 10),
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
  }

  /// هل الصنف مكتمل (يُطبع)؟ — نفس شرط الطباعة من الشاشة.
  static bool isItemComplete(InvoiceItem item) {
    final hasValidQuantity = (item.quantityIndividual != null && item.quantityIndividual! > 0) ||
        (item.quantityLargeUnit != null && item.quantityLargeUnit! > 0);
    return (item.productName.isNotEmpty &&
        hasValidQuantity &&
        (item.appliedPrice > 0 || item.isGift) &&
        (item.itemTotal > 0 || item.isGift) &&
        (item.saleType != null && item.saleType!.isNotEmpty));
  }

  /// 📤 فاتورة محفوظة (مثل نسخة تيليجرام): الأرقام بقواعد الطباعة من الشاشة نفسها حرفياً
  /// (الأصناف المكتملة، الإضافات في اليوم نفسه، التسويات، الواصل، المتبقي، دين العميل)،
  /// ثم الصفحات بالتصميم الأصلي نفسه.
  /// [customerCurrentDebt]: دين العميل الآن (كما تأخذه الطباعة لفاتورة محفوظة).
  static Future<void> addSavedInvoice(
    pw.Document pdf, {
    required Invoice invoice,
    required List<InvoiceItem> items,
    required List<InvoiceAdjustment> adjs,
    required List<Product> allProducts,
    required AppSettings appSettings,
    required pw.Font font,
    required pw.Font alnaserFont,
    required pw.MemoryImage? logoImage,
    required double customerCurrentDebt,
    String customerPhone = '',
    String customerAddress = '',
  }) async {
    await ProductCodes.ensureLoaded();
    final filteredItems = items.where(isItemComplete).toList();
    final itemsTotal = filteredItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final discount = invoice.discount;
    final loadingFee = invoice.loadingFee;
    final settlementsTotal = adjs.fold(0.0, (sum, a) => sum + a.amountDelta);
    final selectedDate = invoice.invoiceDate;
    final invoiceDateOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final sameDayAddedItemAdjs = adjs.where((a) {
      if (a.productId == null) return false;
      if (a.type != 'debit') return false;
      final d = DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day);
      return d == invoiceDateOnly;
    }).toList();
    final itemAdditionsForSection =
        adjs.where((a) => a.productId != null && a.type == 'debit' && !sameDayAddedItemAdjs.contains(a)).toList();
    final itemCreditsForSection = adjs.where((a) => a.productId != null && a.type == 'credit').toList();
    final amountOnlyAdjs = adjs.where((a) => a.productId == null).toList();
    final showSettlementSections = itemAdditionsForSection.isNotEmpty ||
        itemCreditsForSection.isNotEmpty ||
        amountOnlyAdjs.isNotEmpty ||
        sameDayAddedItemAdjs.isNotEmpty;
    final includeSameDayOnlyCase = sameDayAddedItemAdjs.isNotEmpty && !showSettlementSections;
    final sameDayAddsTotal =
        sameDayAddedItemAdjs.fold(0.0, (sum, a) => sum + (a.price ?? 0.0) * (a.quantity ?? 0.0));
    final itemsTotalForDisplay = includeSameDayOnlyCase ? (itemsTotal + sameDayAddsTotal) : itemsTotal;
    final settlementsTotalForDisplay = includeSameDayOnlyCase ? 0.0 : settlementsTotal;
    final preDiscountTotal = itemsTotalForDisplay + settlementsTotalForDisplay + loadingFee;
    final afterDiscount = ((preDiscountTotal - discount).clamp(0.0, double.infinity)).toDouble();
    final paid = invoice.amountPaidOnInvoice;
    final isCash = invoice.paymentType == 'نقد';
    final cashSettlements = showSettlementSections
        ? [...adjs, ...sameDayAddedItemAdjs].where((a) => a.settlementPaymentType == 'نقد').fold(0.0, (sum, a) {
            if (a.productId != null) return sum + (a.price ?? 0.0) * (a.quantity ?? 0.0);
            return sum + a.amountDelta;
          })
        : 0.0;
    final displayedPaidForSettlementsCase =
        (isCash && !showSettlementSections) ? afterDiscount : paid + cashSettlements;
    final remainingForPdf = (isCash && !showSettlementSections) ? 0.0 : afterDiscount - displayedPaidForSettlementsCase;
    // فاتورة محفوظة: الطباعة من الشاشة تعرض دين العميل الحالي (لا تضيف المتبقي مرة ثانية)
    final currentDebtForPdf = customerCurrentDebt;
    final combinedRows = <Map<String, dynamic>>[
      ...filteredItems.map((it) => {'type': 'item', 'item': it}),
      if (includeSameDayOnlyCase) ...sameDayAddedItemAdjs.map((a) => {'type': 'adj', 'adj': a}),
    ];
    await addOriginalPages(
      pdf,
      font: font,
      alnaserFont: alnaserFont,
      logoImage: logoImage,
      appSettings: appSettings,
      combinedRows: combinedRows,
      itemsForPdf: items,
      allProducts: allProducts,
      showSettlementSections: showSettlementSections,
      itemAdditionsForSection: itemAdditionsForSection,
      itemCreditsForSection: itemCreditsForSection,
      amountOnlyAdjs: amountOnlyAdjs,
      invoiceDisplayNumber: invoice.formattedInvoiceNumber,
      customerName: invoice.customerName,
      customerAddress: customerAddress,
      customerPhone: customerPhone,
      selectedDate: selectedDate,
      invoiceToManage: invoice,
      preDiscountTotal: preDiscountTotal,
      discount: discount,
      afterDiscount: afterDiscount,
      loadingFee: loadingFee,
      displayedPaidForSettlementsCase: displayedPaidForSettlementsCase,
      remainingForPdf: remainingForPdf,
      currentDebtForPdf: currentDebtForPdf,
    );
  }
}
