// lib/invoice_designer/designed_rows.dart
//
// صفوف جدول المواد كنصوص لكل عمود (نفس قيم الطباعة الأصلية)، لتُطبع بأي تصميم.

import '../models/invoice_adjustment.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../services/invoice_pdf_service.dart';
import 'invoice_print_data.dart';

class DesignedRows {
  DesignedRows._();

  static String _id5(int? id) => id == null ? '' : id.toString().padLeft(5, '0');

  static Map<String, String> item(int index, InvoiceItem item, Product? product) {
    final qty = item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0;
    final unit = item.saleType ?? '';
    final weight = product?.baseWeight;
    String units = '';
    try {
      units = InvoicePdfService.buildUnitConversionStringForPdf(item, product);
    } catch (_) {}
    return {
      'serial': '${index + 1}',
      'productId': _id5(product?.id),
      'barcode': product?.barcode ?? '',
      'details': item.productName,
      'quantity': '${fmtMoney(qty)} $unit'.trim(),
      'qty': fmtMoney(qty),
      'unit': unit,
      'unitsCount': units,
      'priceBeforeDiscount':
          item.hasLineDiscount ? fmtMoney(item.priceBeforeDiscount ?? item.appliedPrice) : '',
      'discount': item.hasLineDiscount ? item.discountLabel : '',
      'price': fmtMoney(item.appliedPrice),
      'amount': fmtMoney(item.itemTotal),
      'weight': (weight != null && weight > 0) ? '${fmtMoney(weight * qty)} كغ' : '',
      'expiry': product?.hasExpiry == true ? 'له' : '',
      'blank': '',
    };
  }

  static Map<String, String> adjustment(int index, InvoiceAdjustment a, Product? product) {
    final price = a.price ?? 0.0;
    final qty = a.quantity ?? 0.0;
    final total = a.amountDelta != 0.0 ? a.amountDelta : price * qty;
    final unit = a.saleType ?? '';
    final weight = product?.baseWeight;
    return {
      'serial': '${index + 1}',
      'productId': _id5(product?.id),
      'barcode': product?.barcode ?? '',
      'details': a.productName ?? '-',
      'quantity': '${fmtMoney(qty)} $unit'.trim(),
      'qty': fmtMoney(qty),
      'unit': unit,
      'unitsCount': a.unitsInLargeUnit == null ? '' : fmtMoney(a.unitsInLargeUnit!),
      'priceBeforeDiscount': '',
      'discount': '',
      'price': fmtMoney(price),
      'amount': fmtMoney(total),
      'weight': (weight != null && weight > 0) ? '${fmtMoney(weight * qty)} كغ' : '',
      'expiry': product?.hasExpiry == true ? 'له' : '',
      'blank': '',
    };
  }

  /// صف من إيصال نقطة البيع
  static Map<String, String> simple(int index, String name, num qty, String? unit, double price) => {
        'serial': '${index + 1}',
        'productId': '',
        'barcode': '',
        'details': name,
        'quantity': '${fmtMoney(qty)} ${unit ?? ''}'.trim(),
        'qty': fmtMoney(qty),
        'unit': unit ?? '',
        'unitsCount': '',
        'priceBeforeDiscount': '',
        'discount': '',
        'price': fmtMoney(price),
        'amount': fmtMoney(price * qty),
        'weight': '',
        'expiry': '',
        'blank': '',
      };
}
