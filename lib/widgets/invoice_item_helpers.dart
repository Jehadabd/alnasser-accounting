// widgets/invoice_item_helpers.dart
import '../models/invoice_item.dart';

bool isInvoiceItemComplete(InvoiceItem item) {
  return (item.productName.isNotEmpty &&
      (item.quantityIndividual != null || item.quantityLargeUnit != null) &&
      item.appliedPrice > 0 &&
      item.itemTotal > 0 &&
      (item.saleType != null && item.saleType!.isNotEmpty));
}
