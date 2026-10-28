// lib/invoice_designer/invoice_print_data.dart
//
// 📄 بيانات فاتورة جاهزة للطباعة بأي تصميم: الشركة، الحقول، صفوف المواد (نصوص
// لكل عمود)، والمجاميع. تُبنى من شاشة الفاتورة أو نقطة البيع، أو بيانات تجريبية
// للمعاينة في المصمم.

import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../erp/arabic_words.dart';
import '../models/app_settings.dart';
import '../services/auth_service.dart';
import '../services/logo_service.dart';
import '../services/settings_manager.dart';

String fmtMoney(num v) => NumberFormat('#,##0.##', 'en_US').format(v);

/// معلومات الشركة (من «تخصيص الفاتورة المطبوعة»)
class PrintCompany {
  const PrintCompany({
    required this.name,
    this.lines = const {},
    this.logo,
    this.footerNote = '',
    this.branch = '',
  });

  final String name;

  /// description / address / phones / tax / cr
  final Map<String, String> lines;
  final Uint8List? logo;
  final String footerNote;
  final String branch;

  static Future<PrintCompany> load([AppSettings? s]) async {
    s ??= await SettingsManager.getAppSettings();
    final d = s.invoiceDesign;
    // ☎️ كل رقم باسمه إن سُمّي («كهربائيات: 0770…»)
    final phones = d.labeledPhones.isNotEmpty ? d.labeledPhones : s.phoneNumbers;
    Uint8List? logo;
    try {
      logo = await LogoService.getLogoBytes(appSettings: s);
    } catch (_) {}
    return PrintCompany(
      name: d.companyName.replaceAll('ـ', '').trim(),
      lines: {
        if (s.companyDescription.trim().isNotEmpty) 'description': s.companyDescription.trim(),
        if (d.companyAddress.trim().isNotEmpty) 'address': d.companyAddress.trim(),
        if (phones.where((p) => p.trim().isNotEmpty).isNotEmpty)
          'phones': phones.where((p) => p.trim().isNotEmpty).join(' - '),
        if (d.taxNumber.trim().isNotEmpty) 'tax': 'الرقم الضريبي: ${d.taxNumber.trim()}',
        if (d.commercialRegister.trim().isNotEmpty) 'cr': 'السجل التجاري: ${d.commercialRegister.trim()}',
      },
      logo: logo,
      footerNote: d.footerNote.trim(),
      branch: s.branchName.trim(),
    );
  }
}

class InvoicePrintData {
  InvoicePrintData({
    required this.company,
    required Map<String, String> fields,
    required this.rows,
    required this.totals,
    this.paymentType = 'نقد',
  }) : fields = {
          // 🖨️ لحظة الطباعة ومن يطبع (المحاسب = من سجّل، يمرّره المستدعي)
          'printedAt': _nowText(),
          'printedBy': AuthService().currentUser?.shownName ?? '',
          'footer': company.footerNote,
          'branch': company.branch,
          'itemsCount': '${rows.length}',
          if (totals['net'] != null) 'amountWords': ArabicWords.money(totals['net']!),
          ...fields,
        };

  final PrintCompany company;
  final Map<String, String> fields;

  /// كل صف: معرّف العمود ← النص
  final List<Map<String, String>> rows;
  final Map<String, double> totals;
  final String paymentType;

  String field(String key) => fields[key] ?? '';

  /// مفتاح بيانات الباركود: كل بيانات الفاتورة في رمز QR واحد.
  static const String barcodeInvoiceInfo = 'invoiceInfo';

  /// 🧾 كل بيانات الفاتورة لرمز QR: الرقم، التاريخ والوقت، السيد، الهاتف.
  String get invoiceInfoText => [
        if (field('invoiceNo').isNotEmpty) 'رقم الفاتورة: ${field('invoiceNo')}',
        if (field('dateTime').isNotEmpty) 'التاريخ: ${field('dateTime')}',
        if (field('customer').isNotEmpty) 'السيد: ${field('customer')}',
        if (field('phone').isNotEmpty) 'الهاتف: ${field('phone')}',
      ].join('\n');

  /// نص الباركود لمفتاح [key]. الباركود العادي (Code128) لا يحمل إلا حروفاً
  /// لاتينية وأرقاماً — نص عربي يُفشل الطباعة كلها، فيُستعمل رقم الفاتورة.
  String barcodeText(String key, {required bool qr}) {
    final text = key == barcodeInvoiceInfo ? invoiceInfoText : field(key);
    if (!qr && text.codeUnits.any((c) => c > 127)) return field('invoiceNo');
    return text;
  }

  /// قيمة بند من المجاميع كنص
  String totalText(String key) {
    if (key == 'paymentType') return paymentType;
    if (key == 'itemsCount') return '${rows.length}';
    final v = totals[key];
    return v == null ? '' : fmtMoney(v);
  }

  /// يستبدل {المفتاح} في النص الحر بقيمته
  String fill(String template) => template.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (m) {
          final k = m.group(1)!;
          if (fields.containsKey(k)) return fields[k]!;
          if (totals.containsKey(k)) return fmtMoney(totals[k]!);
          if (k == 'company') return company.name;
          return m.group(0)!;
        },
      );

  static String two(int n) => n.toString().padLeft(2, '0');

  static String _nowText() {
    final n = DateTime.now();
    return '${dateText(n)} ${timeText(n)}';
  }

  /// بيانات تجريبية لسند (معاينة مصمم السندات)
  static InvoicePrintData sampleVoucher(PrintCompany company, String kind) {
    final now = DateTime.now();
    final receipt = kind == 'receipt';
    final cash = kind == 'cash_receipt' || kind == 'cash_refund';
    final minus = kind == 'cash_refund' || kind == 'credit_note';
    final title = switch (kind) {
      'receipt' => 'سند قبض',
      'cash_receipt' => 'سند قبض — إضافة على فاتورة',
      'cash_refund' => 'سند صرف — مرتجع بضاعة',
      'debit_note' => 'إشعار مدين',
      _ => 'إشعار دائن',
    };
    Map<String, String> row(Map<String, String> m) => {
          for (final k in const [
            'serial', 'productId', 'barcode', 'itemCode', 'details', 'quantity', 'qty', 'unit', 'unitsCount',
            'priceBeforeDiscount', 'discount', 'price', 'amount', 'weight', 'expiry', 'blank'
          ])
            k: m[k] ?? '',
        };
    final rows = receipt
        ? [
            row({'serial': '1', 'details': 'محمد أحمد', 'priceBeforeDiscount': '250,000', 'price': '250,000',
                'amount': '100,000', 'blank': '150,000'}),
          ]
        : [
            row({'serial': '1', 'details': 'لمبة LED 18 واط — ${minus ? 'مرتجع' : 'إضافة'}', 'quantity': '5 قطعة',
                'qty': '5', 'unit': 'قطعة', 'price': '1,500', 'amount': '7,500', 'blank': minus ? 'مرتجع' : 'إضافة'}),
            row({'serial': '2', 'details': 'شريط عازل — ${minus ? 'مرتجع' : 'إضافة'}', 'quantity': '2 لفة',
                'qty': '2', 'unit': 'لفة', 'price': '2,500', 'amount': '5,000', 'blank': minus ? 'مرتجع' : 'إضافة'}),
          ];
    const amount = 12500.0;
    return InvoicePrintData(
      company: company,
      fields: {
        'voucherTitle': title,
        'voucherNo': '15',
        'invoiceNo': receipt ? '15' : '1202610045',
        'date': dateText(now),
        'time': timeText(now),
        'dateTime': '${dateText(now)} ${timeText(now)}',
        'customer': 'محمد أحمد',
        'phone': '07701234567',
        'address': 'الموصل - حي الزهور',
        'paymentType': receipt || cash ? 'نقد' : 'دين',
        'voucherReason': receipt ? 'تسديد دين' : 'تعديل على الفاتورة رقم 1202610045',
        'boxName': 'الصندوق الرئيسي',
        'docNo': '',
        'user': 'الكاشير',
        'accountant': 'علي المحاسب',
      },
      rows: rows,
      totals: receipt
          ? {'voucherAmount': 100000, 'net': 100000, 'paid': 100000, 'previousDebt': 250000, 'currentDebt': 150000}
          : {
              'voucherAmount': amount,
              'net': amount,
              'invoiceBefore': 100000,
              'invoiceAfter': minus ? 100000 - amount : 100000 + amount,
              if (!cash) 'previousDebt': 250000,
              if (!cash) 'currentDebt': minus ? 250000 - amount : 250000 + amount,
            },
      paymentType: receipt || cash ? 'نقد' : 'دين',
    );
  }
  static String dateText(DateTime d) => '${two(d.day)}-${two(d.month)}-${d.year}';
  static String timeText(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

  /// بيانات تجريبية للمعاينة في المصمم
  static InvoicePrintData sample(PrintCompany company, {int rows = 6}) {
    const names = [
      'قاطع كهربائي 32 أمبير',
      'كيبل نحاس 2×4 ملم',
      'مفتاح إنارة مزدوج',
      'لمبة LED 18 واط',
      'بلاك أرضي 3 فتحات',
      'شريط عازل',
      'علبة توزيع 12 خط',
      'محول 220/12 فولت',
    ];
    const units = ['قطعة', 'متر', 'قطعة', 'كرتونة', 'قطعة', 'لفة', 'قطعة', 'قطعة'];
    final list = <Map<String, String>>[];
    final now = DateTime.now();
    var sum = 0.0;
    for (var i = 0; i < rows; i++) {
      final qty = (i % 4) + 1.0;
      final price = 2500.0 + i * 1750;
      final amount = qty * price;
      sum += amount;
      list.add({
        'serial': '${i + 1}',
        'productId': (1000 + i * 7).toString().padLeft(5, '0'),
        'barcode': '62${(1234560 + i)}',
        'itemCode': 'M${(100 + i * 3)}',
        'details': names[i % names.length],
        'quantity': '${fmtMoney(qty)} ${units[i % units.length]}',
        'qty': fmtMoney(qty),
        'unit': units[i % units.length],
        'unitsCount': i % 3 == 0 ? '12' : '',
        'priceBeforeDiscount': i == 1 ? fmtMoney(price + 500) : '',
        'discount': i == 1 ? '500' : '',
        'price': fmtMoney(price),
        'amount': fmtMoney(amount),
        'weight': '${fmtMoney(qty * (0.25 + i * 0.5))} كغ',
        'expiry': '${now.year + 1 + i % 2}/${((i * 3) % 12 + 1).toString().padLeft(2, '0')}',
        'blank': '',
      });
    }
    const discount = 1000.0;
    const loading = 2000.0;
    final net = sum - discount + loading;
    const paid = 20000.0;
    return InvoicePrintData(
      company: company,
      fields: {
        'invoiceNo': '1202610${list.length + 40}',
        'date': dateText(now),
        'time': timeText(now),
        'dateTime': '${dateText(now)} ${timeText(now)}',
        'customer': 'محمد أحمد',
        'phone': '07701234567',
        'address': 'الموصل - حي الزهور',
        'paymentType': 'دين',
        'user': 'الكاشير',
        'preparer': 'أحمد المجهز',
        'accountant': 'علي المحاسب',
        'copy': '',
        'voucherTitle': 'إشعار دائن',
        'voucherNo': 'س-15',
        'voucherReason': 'إرجاع بضاعة تالفة',
      },
      rows: list,
      totals: {
        'beforeDiscount': sum + loading,
        'discount': discount,
        'afterDiscount': net,
        'loadingFee': loading,
        'net': net,
        'paid': paid,
        'remaining': net - paid,
        'previousDebt': 50000,
        'currentDebt': 50000 + net - paid,
        'voucherAmount': 12500,
        'invoiceBefore': net,
        'invoiceAfter': net - 12500,
      },
      paymentType: 'دين',
    );
  }
}
