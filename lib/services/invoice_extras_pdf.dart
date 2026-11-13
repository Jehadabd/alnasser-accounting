// lib/services/invoice_extras_pdf.dart
//
// ⚖️🛡️ ما يُطبع تحت جدول المواد في التصميم الأصلي (PrintedInvoicePdf و InvoicePdfService)،
// بالقواعد نفسها التي يطبع بها «مصمم الفواتير»:
//   • وزن الفاتورة = مجموع (وزن الوحدة الأساسية × الكمية بالوحدة الأساسية) للمواد التي لها وزن.
//   • شروط الضمان كما ثُبِّتت على سطور الفاتورة عند البيع (ItemWarranty.termsNote).

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../erp/warranty/item_warranty.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';

class InvoiceExtrasPdf {
  InvoiceExtrasPdf._();

  static Product? _productOf(InvoiceItem it, List<Product> products) {
    for (final p in products) {
      if (it.productId != null ? p.id == it.productId : p.name == it.productName) return p;
    }
    if (it.productId != null) {
      for (final p in products) {
        if (p.name == it.productName) return p;
      }
    }
    return null;
  }

  /// وزن الفاتورة بالكيلو (0 إن لم يكن لأي مادة وزن).
  static double weightOf(Iterable<InvoiceItem> items, List<Product> products) {
    var sum = 0.0;
    for (final it in items) {
      final w = _productOf(it, products)?.baseWeight;
      if (w != null && w > 0) sum += w * it.baseQuantity;
    }
    return sum;
  }

  static String weightText(double kg) => '${NumberFormat('#,##0.##', 'en_US').format(kg)} كغم';

  /// نص «شروط الضمان» (فارغ إن لم تكن).
  static String termsOf(Iterable<InvoiceItem> items) =>
      ItemWarranty.termsNote([for (final it in items) if (it.hasWarranty) (it.productName, it.warrantyTerms)]);

  /// مربع يوضع تحت الجدول في الصفحة الأخيرة: وزن الفاتورة ثم شروط الضمان. لا شيء إن خلا منهما.
  static List<pw.Widget> block(Iterable<InvoiceItem> items, List<Product> products, pw.Font font) {
    final kg = weightOf(items, products);
    final terms = termsOf(items);
    if (kg <= 0 && terms.isEmpty) return const [];
    final st = pw.TextStyle(font: font, fontSize: 9.5);
    return [
      if (kg > 0)
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('وزن الفاتورة: ${weightText(kg)}',
              style: pw.TextStyle(font: font, fontSize: 10.5), textDirection: pw.TextDirection.rtl),
        ),
      if (terms.isNotEmpty)
        pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(top: 3, bottom: 3),
          padding: const pw.EdgeInsets.all(5),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('شروط الضمان', style: pw.TextStyle(font: font, fontSize: 10), textDirection: pw.TextDirection.rtl),
            pw.Text(terms, style: st, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right),
          ]),
        ),
    ];
  }
}
