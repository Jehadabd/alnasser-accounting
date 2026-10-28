// lib/invoice_designer/designed_rows.dart
//
// صفوف جدول المواد كنصوص لكل عمود (نفس قيم الطباعة الأصلية)، لتُطبع بأي تصميم.

import '../models/invoice_adjustment.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../services/invoice_pdf_service.dart';
import '../services/product_codes.dart';
import 'invoice_print_data.dart';

class DesignedRows {
  DesignedRows._();

  static String _id5(int? id) => id == null ? '' : id.toString().padLeft(5, '0');

  /// تاريخ انتهاء المادة (سنة/شهر) — فارغ إن لم يُسجَّل لها تاريخ.
  static String _expiry(Product? p) {
    final d = p?.expiryDate;
    if (d == null) return '';
    return '${d.year}/${d.month.toString().padLeft(2, '0')}';
  }

  static String _weight(Product? p, double baseQty) {
    final w = p?.baseWeight;
    return (w != null && w > 0) ? '${fmtMoney(w * baseQty)} كغ' : '';
  }

  static Map<String, String> item(int index, InvoiceItem item, Product? product) {
    final qty = item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0;
    final unit = item.saleType ?? '';
    // الوزن بالوحدة الأساسية: كرتون ×24 قطعة يزن 24 ضعف القطعة
    final large = item.quantityLargeUnit ?? 0;
    final per = item.unitsInLargeUnit ?? 0;
    final baseQty = (large > 0 && per > 0) ? large * per : qty;
    String units = '';
    try {
      units = InvoicePdfService.buildUnitConversionStringForPdf(item, product);
    } catch (_) {}
    return {
      'serial': '${index + 1}',
      'productId': _id5(product?.id),
      'barcode': product?.barcode ?? '',
      'itemCode': ProductCodes.codeOf(product?.id) ?? '',
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
      'weight': _weight(product, baseQty),
      'expiry': _expiry(product),
      'blank': '',
    };
  }

  static Map<String, String> adjustment(int index, InvoiceAdjustment a, Product? product) {
    final price = a.price ?? 0.0;
    final qty = a.quantity ?? 0.0;
    final total = a.amountDelta != 0.0 ? a.amountDelta : price * qty;
    final unit = a.saleType ?? '';
    final per = a.unitsInLargeUnit ?? 0;
    final baseQty = per > 0 ? qty * per : qty;
    return {
      'serial': '${index + 1}',
      'productId': _id5(product?.id),
      'barcode': product?.barcode ?? '',
      'itemCode': ProductCodes.codeOf(product?.id) ?? '',
      'details': a.productName ?? '-',
      'quantity': '${fmtMoney(qty)} $unit'.trim(),
      'qty': fmtMoney(qty),
      'unit': unit,
      'unitsCount': a.unitsInLargeUnit == null ? '' : fmtMoney(a.unitsInLargeUnit!),
      'priceBeforeDiscount': '',
      'discount': '',
      'price': fmtMoney(price),
      'amount': fmtMoney(total),
      'weight': _weight(product, baseQty),
      'expiry': _expiry(product),
      'blank': '',
    };
  }

  /// صف من إيصال نقطة البيع
  static Map<String, String> simple(int index, String name, num qty, String? unit, double price) => {
        'serial': '${index + 1}',
        'productId': '',
        'barcode': '',
        'itemCode': '',
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
