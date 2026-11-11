// lib/services/invoice_safety/iqd_normalize.dart
//
// 💵 تقريب مبالغ المستندات إلى دنانير صحيحة قبل حفظها (lib/utils/iqd.dart).
//
// أسطر فاتورة البيع تُقرَّب في InvoiceItem نفسه (فيراها المستخدم مقرَّبة وهو
// يكتب). هنا رأس المستند: الخصم والأجور والمسدد والإجمالي، وفواتير الشراء
// بالدينار. لا شيء يُضاف أو يُحذف: المبالغ نفسها لأقرب دينار، والنصف لصالح المحل.

import '../../models/invoice.dart';
import '../../models/invoice_input_data.dart';
import '../../models/purchase_invoice.dart';
import '../../models/purchase_invoice_item.dart';
import '../../utils/iqd.dart';

class IqdNormalize {
  IqdNormalize._();

  /// بيانات فاتورة البيع من الشاشة ← مبالغ صحيحة. يعيد الكائن نفسه إن لم يتغير شيء.
  static InvoiceInputData invoiceInput(InvoiceInputData d) {
    final items = d.invoiceItems.fold<double>(0, (s, i) => s + i.itemTotal);
    final t = Iqd.invoiceTotals(
      itemsTotal: items,
      discount: d.discount,
      loadingFee: d.loadingFee,
      paid: d.paidAmount,
    );
    if (t.discount == d.discount && t.loadingFee == d.loadingFee && t.paid == d.paidAmount) return d;
    return InvoiceInputData(
      invoiceToManage: d.invoiceToManage,
      customerName: d.customerName,
      customerPhone: d.customerPhone,
      customerAddress: d.customerAddress,
      installerName: d.installerName,
      pointsRate: d.pointsRate,
      paidAmount: t.paid,
      loadingFee: t.loadingFee,
      discount: t.discount,
      paymentType: d.paymentType,
      selectedDate: d.selectedDate,
      invoiceItems: d.invoiceItems,
    );
  }

  /// رأس فاتورة بيع (يُعدَّل في مكانه). مجموع الأسطر يُشتق من الرأس نفسه
  /// (الإجمالي − الأجور + الخصم) ما لم يُعطَ [itemsTotal].
  ///
  /// [headerToo] = false ⇒ مبلغ الإرجاع القديم وحده (فاتورة محفوظة: مبالغها
  /// يحسمها مسار الحفظ؛ تحديث حقل آخر فيها لا يغيّر مبلغاً بصمت).
  static Invoice invoice(Invoice inv, {double? itemsTotal, bool headerToo = true}) {
    inv.returnAmount = Iqd.down(inv.returnAmount);
    if (!headerToo) return inv;
    final items = itemsTotal ?? (inv.totalAmount - inv.loadingFee + inv.discount);
    final t = Iqd.invoiceTotals(
      itemsTotal: items,
      discount: inv.discount,
      loadingFee: inv.loadingFee,
      paid: inv.amountPaidOnInvoice,
    );
    // المسدد = الإجمالي المكتوب في الرأس (نقد، أو دين مسدد كاملاً) ⇒ الإجمالي الجديد
    // نفسه، حتى لو اختلف مجموع الأسطر المقرَّبة عن الرأس قبل تقريبه
    final paid = (inv.amountPaidOnInvoice - inv.totalAmount).abs() <= 0.01 ? t.total : t.paid;
    inv
      ..discount = t.discount
      ..loadingFee = t.loadingFee
      ..amountPaidOnInvoice = paid
      ..totalAmount = t.total;
    return inv;
  }

  /// فاتورة شراء: بالدينار فقط (الدولار يبقى بكسوره). ما علينا للمورد ← [Iqd.down]
  /// عند النصف، وما ندفعه له ← [Iqd.up]. سعر الوحدة يبقى كما كُتب (كلفة).
  static (PurchaseInvoice, List<PurchaseInvoiceItem>) purchase(
      PurchaseInvoice inv, List<PurchaseInvoiceItem> items) {
    if (inv.currency != 'IQD') return (inv, items);
    final rawItems = items.fold<double>(0, (s, i) => s + i.totalPrice);
    var itemsChanged = false;
    final newItems = <PurchaseInvoiceItem>[];
    for (final i in items) {
      final w = Iqd.down(i.totalPrice);
      if (w == i.totalPrice) {
        newItems.add(i);
      } else {
        itemsChanged = true;
        newItems.add(i.copyWith(totalPrice: w));
      }
    }
    final itemsSum = newItems.fold<double>(0, (s, i) => s + i.totalPrice);
    // الإجمالي = مجموع الأسطر (إن كان كذلك قبل التقريب)، وإلا يُقرَّب وحده
    final total = (inv.totalAmount - rawItems).abs() <= 0.01 && items.isNotEmpty
        ? itemsSum
        : Iqd.down(inv.totalAmount);
    double paid;
    if ((inv.paidAmount - inv.totalAmount).abs() <= 0.01) {
      paid = total;
    } else {
      paid = Iqd.up(inv.paidAmount);
      if (inv.paidAmount <= inv.totalAmount + 0.01 && paid > total) paid = total;
    }
    if (total == inv.totalAmount && paid == inv.paidAmount && !itemsChanged) {
      return (inv, items);
    }
    return (inv.copyWith(totalAmount: total, paidAmount: paid), newItems);
  }
}
