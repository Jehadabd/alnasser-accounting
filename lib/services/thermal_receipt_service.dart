// services/thermal_receipt_service.dart
// خدمة إنشاء وطباعة الإيصالات الحرارية باستخدام PDF للنص العربي

import 'dart:typed_data';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:intl/intl.dart';

/// بيانات صنف في الإيصال
class ReceiptItem {
  final String name;
  final int quantity;
  final double price;
  final String? unit;

  ReceiptItem({
    required this.name,
    required this.quantity,
    required this.price,
    this.unit,
  });

  double get total => price * quantity;
}

/// بيانات الإيصال الكاملة
class ReceiptData {
  final String invoiceId; // رقم الفاتورة المركّب للعرض
  final DateTime dateTime;
  final List<ReceiptItem> items;
  final double subtotal;
  final double discount;
  final double total;
  final double paidAmount;
  final String? customerName;
  final String paymentType;

  ReceiptData({
    required this.invoiceId,
    required this.dateTime,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paidAmount,
    this.customerName,
    required this.paymentType,
  });

  double get remainingAmount => (total - paidAmount).clamp(0, double.infinity);
}

/// خدمة الطباعة الحرارية
class ThermalReceiptService {
  static final ThermalReceiptService _instance = ThermalReceiptService._internal();
  factory ThermalReceiptService() => _instance;
  ThermalReceiptService._internal();

  pw.Font? _arabicFont;
  pw.MemoryImage? _logoImage;

  /// تحميل الخط العربي واللوجو
  Future<void> _loadAssets(String? logoPath) async {
    try {
      // تحميل الخط
      if (_arabicFont == null) {
        final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
        _arabicFont = pw.Font.ttf(fontData);
      }
      
      // تحميل اللوجو من الإعدادات أو الافتراضي
      if (logoPath != null && logoPath.isNotEmpty) {
        try {
          final file = File(logoPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            _logoImage = pw.MemoryImage(bytes);
          }
        } catch (e) {
          print('تعذر تحميل اللوجو المخصص: $e');
        }
      }
      
      // استخدام اللوجو الافتراضي إذا لم يتم تحميل المخصص
      if (_logoImage == null) {
        try {
          final logoData = await rootBundle.load('assets/icon/alnasser.jpg');
          _logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
        } catch (e) {
          print('تعذر تحميل اللوجو الافتراضي: $e');
        }
      }
    } catch (e) {
      print('خطأ في تحميل الأصول: $e');
    }
  }

  /// طباعة إيصال POS
  Future<bool> printReceipt(ReceiptData receipt) async {
    try {
      // جلب الطابعة الحرارية المحفوظة
      final printer = await SettingsManager.getPosThermalPrinter();
      if (printer == null) {
        print('🖨️ لم يتم تحديد طابعة حرارية');
        return false;
      }

      // جلب إعدادات الشركة من تصميم الفاتورة
      final settings = await SettingsManager.getAppSettings();
      final invoiceDesign = settings.invoiceDesign;
      
      // قراءة البيانات من تخصيص الفاتورة
      String companyName = invoiceDesign.companyName;
      // إزالة الفواصل الزائدة من اسم الشركة
      companyName = companyName.replaceAll('ـ', '');
      
      String phoneNumber = '';
      if (invoiceDesign.phoneNumbers.isNotEmpty) {
        phoneNumber = invoiceDesign.phoneNumbers.first;
      } else if (settings.phoneNumbers.isNotEmpty) {
        phoneNumber = settings.phoneNumbers.first;
      }
      
      String? logoPath = invoiceDesign.logoPath;

      // تحميل الأصول
      await _loadAssets(logoPath);

      // إنشاء PDF
      final pdf = await _buildReceiptPdf(receipt, companyName, phoneNumber);

      // طباعة على الطابعة المحددة
      await Printing.directPrintPdf(
        printer: Printer(url: printer.name),
        onLayout: (format) => pdf,
        name: 'فاتورة #${receipt.invoiceId}',
      );
      
      print('🖨️ تم طباعة الإيصال بنجاح - فاتورة #${receipt.invoiceId}');
      return true;
      
    } catch (e) {
      print('❌ خطأ في طباعة الإيصال: $e');
      return false;
    }
  }

  /// إنشاء PDF للإيصال
  Future<Uint8List> _buildReceiptPdf(ReceiptData receipt, String companyName, String phoneNumber) async {
    // إعدادات الورق للطابعة الحرارية (80mm - عرض الطباعة الفعلي ~72-75mm)
    const receiptWidth = 72.0 * PdfPageFormat.mm;
    
    final pdf = pw.Document();

    final baseStyle = pw.TextStyle(
      font: _arabicFont,
      fontSize: 9, // تصغير الخط ليناسب 58mm
    );
    
    final boldStyle = pw.TextStyle(
      font: _arabicFont,
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
    );
    
    final titleStyle = pw.TextStyle(
      font: _arabicFont,
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    );

    final smallStyle = pw.TextStyle(
      font: _arabicFont,
      fontSize: 8,
    );
    
    final tableHeaderStyle = pw.TextStyle(
      font: _arabicFont,
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(receiptWidth, double.infinity, marginAll: 0.5), // هوامش شبه معدومة (0.5mm)
        textDirection: pw.TextDirection.rtl,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ═══════════════════════════════════════════════════════════
              // رأس الإيصال - اللوجو واسم الشركة ورقم الهاتف
              // ═══════════════════════════════════════════════════════════
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // اسم الشركة ورقم الهاتف (يمين)
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(companyName.isNotEmpty ? companyName : 'الناصر', 
                          style: titleStyle, 
                          textAlign: pw.TextAlign.right,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        if (phoneNumber.isNotEmpty)
                          pw.Text(phoneNumber, style: baseStyle, textAlign: pw.TextAlign.right),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  // اللوجو (يسار)
                  if (_logoImage != null)
                    pw.Container(
                      width: 55, // تكبير عرض اللوجو
                      height: 55,
                      child: pw.Image(_logoImage!),
                    ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 2),
              
              // ═══════════════════════════════════════════════════════════
              // رقم الفاتورة والتاريخ (كل واحد في سطر)
              // ═══════════════════════════════════════════════════════════
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start, // لضمان محاذاة العرض
                children: [
                  // رقم الفاتورة (يمين)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, // لتوزيع المساحة
                    children: [
                      pw.Expanded(
                        child: pw.Text('فاتورة #${receipt.invoiceId}', 
                          style: boldStyle, 
                          textAlign: pw.TextAlign.right, 
                          textDirection: pw.TextDirection.rtl
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 1),
                  // التاريخ والوقت (يمين - تحت رقم الفاتورة)
                  pw.Text(_formatDateTime(receipt.dateTime), 
                    style: smallStyle, 
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl
                  ),
                ],
              ),
              
              // اسم العميل (إذا وجد)
              if (receipt.customerName != null && receipt.customerName!.isNotEmpty)
                pw.Container(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('العميل: ${receipt.customerName}', 
                    style: baseStyle, 
                    textDirection: pw.TextDirection.rtl),
                ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 2),
              
              // ═══════════════════════════════════════════════════════════
              // رأس الجدول: الصنف | العدد | السعر (سعر القطعة)
              // ═══════════════════════════════════════════════════════════
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                decoration: pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text('الصنف', style: tableHeaderStyle, textAlign: pw.TextAlign.right, textDirection: pw.TextDirection.rtl),
                    ),
                    pw.SizedBox(
                      width: 25,
                      child: pw.Text('عدد', style: tableHeaderStyle, textAlign: pw.TextAlign.center),
                    ),
                    pw.SizedBox(
                      width: 45, // زيادة العرض قليلاً للأرقام الكبيرة
                      child: pw.Text('سعر', style: tableHeaderStyle, textAlign: pw.TextAlign.center),
                    ),
                  ],
                ),
              ),
              
              // ═══════════════════════════════════════════════════════════
              // صفوف الأصناف
              // ═══════════════════════════════════════════════════════════
              ...receipt.items.map((item) => pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text(item.name, 
                        style: baseStyle, 
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                        maxLines: 2,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                    pw.SizedBox(
                      width: 25,
                      child: pw.Text('${item.quantity}', style: baseStyle, textAlign: pw.TextAlign.center),
                    ),
                    pw.SizedBox(
                      width: 45,
                      // عرض سعر القطعة الواحدة كما طلب المستخدم
                      child: pw.Text(_formatNumber(item.price), style: baseStyle, textAlign: pw.TextAlign.center),
                    ),
                  ],
                ),
              )),
              
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 2),
              
              // ═══════════════════════════════════════════════════════════
              // المجاميع (محاذاة التسميات تحت عمود الصنف - يمين)
              // ═══════════════════════════════════════════════════════════
              // الإجمالي قبل الخصم
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                   // التسمية (يمين)
                  pw.Text('الإجمالي قبل الخصم:', style: baseStyle, textDirection: pw.TextDirection.rtl),
                  // القيمة (يسار)
                  pw.Text(_formatNumber(receipt.subtotal), style: baseStyle),
                ],
              ),
              
              // الخصم
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('الخصم:', style: baseStyle, textDirection: pw.TextDirection.rtl),
                  pw.Text(_formatNumber(receipt.discount), style: baseStyle),
                ],
              ),
              
              // الإجمالي النهائي
              pw.SizedBox(height: 4),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الإجمالي:', style: boldStyle, textDirection: pw.TextDirection.rtl),
                    pw.Text(_formatNumber(receipt.total), style: pw.TextStyle(font: _arabicFont, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              
              // المدفوع والمتبقي (للدين)
              if (receipt.paymentType == 'دين' && receipt.remainingAmount > 0) ...[
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(_formatNumber(receipt.paidAmount), style: baseStyle),
                    pw.Text('المدفوع:', style: baseStyle, textDirection: pw.TextDirection.rtl),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(_formatNumber(receipt.remainingAmount), style: boldStyle),
                    pw.Text('المتبقي:', style: boldStyle, textDirection: pw.TextDirection.rtl),
                  ],
                ),
              ],
              
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 10),
              
              // ═══════════════════════════════════════════════════════════
              // ذيل الإيصال
              // ═══════════════════════════════════════════════════════════
              pw.Center(child: pw.Text('شكراً لتعاملكم معنا', style: smallStyle, textDirection: pw.TextDirection.rtl)),
              pw.SizedBox(height: 2),
              pw.Center(child: pw.Text('تطبيق الناصر', style: boldStyle, textDirection: pw.TextDirection.rtl)),
              pw.SizedBox(height: 20), // مسافة للقطع
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// تنسيق الرقم (فواصل الآلاف + بدون أصفار عشرية زائدة)
  String _formatNumber(double value) {
    // تنسيق مع فواصل الآلاف
    final formatter = NumberFormat("#,##0.##", "en_US");
    return formatter.format(value);
  }

  /// تنسيق التاريخ والوقت
  String _formatDateTime(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
           '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// طباعة إيصال تجريبي
  Future<bool> printTestReceipt() async {
    final testReceipt = ReceiptData(
      invoiceId: '0',
      dateTime: DateTime.now(),
      items: [
        ReceiptItem(name: 'منتج تجريبي للاختبار', quantity: 2, price: 50.0),
        ReceiptItem(name: 'منتج آخر', quantity: 1, price: 100.0),
      ],
      subtotal: 200.0,
      discount: 20.0,
      total: 180.0,
      paidAmount: 180.0,
      paymentType: 'نقد',
    );
    
    return await printReceipt(testReceipt);
  }
}
