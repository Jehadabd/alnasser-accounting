// lib/services/saved_invoice_print_pdf.dart
//
// 🖨️ PDF فاتورة محفوظة «كما تُطبع من شاشة الفاتورة» حرفياً — لمن لا يفتح الشاشة (قائمة
// «تعديل الفواتير»: المشاركة والإرسال عبر واتساب):
//   • نفس التصميم: «مصمم الفاتورة» إن كان مختاراً لهذا النوع، وإلا التصميم الأصلي الموحّد
//     (PrintedInvoicePdf — نفسه للطباعة وتيليجرام).
//   • نفس الأرقام بقواعد generateInvoicePdf في invoice_actions.dart: الأصناف المكتملة، إضافات
//     اليوم نفسه، التسويات، الواصل، المتبقي، ودين العميل (بالاسم بلا مسافات).
//   • نفس الشعار والخطوط (LogoService)، ورقم الفاتورة المركّب، والهاتف والعنوان، والمجهز والمحاسب.
// يقرأ فقط: لا يغيّر فاتورة ولا ديناً ولا معاملة.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import '../invoice_designer/designed_rows.dart';
import '../invoice_designer/invoice_layout_store.dart';
import '../invoice_designer/invoice_print_data.dart';
import '../invoice_designer/layout_pdf_renderer.dart';
import '../models/invoice.dart';
import '../models/invoice_adjustment.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import 'auth_service.dart';
import 'database/business/customer_name_rule.dart';
import 'database_service.dart';
import 'invoice_staff_service.dart';
import 'logo_service.dart';
import 'printed_invoice_pdf.dart';
import 'product_codes.dart';
import 'settings_manager.dart';
import 'voucher_print.dart';

class SavedInvoicePrintPdf {
  SavedInvoicePrintPdf._();

  /// بايتات PDF الفاتورة [invoice] كما تخرج من «طباعة» في شاشتها (A4 افتراضياً).
  static Future<Uint8List> build(Invoice invoice, {String target = 'invoice_a4'}) async {
    final id = invoice.id;
    if (id == null) throw StateError('الفاتورة غير محفوظة');
    final db = DatabaseService();
    final appSettings = await SettingsManager.getAppSettings();
    await ProductCodes.refresh(); // 🏷️ رموز المواد للطباعة (أحدث نسخة)

    final items = await db.getInvoiceItems(id);
    final allProducts = await db.getAllProducts();
    final filteredItems = items.where(PrintedInvoicePdf.isItemComplete).toList();
    final itemsTotal = filteredItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final discount = invoice.discount;
    final loadingFee = invoice.loadingFee;

    List<InvoiceAdjustment> adjs = [];
    double settlementsTotal = 0.0;
    try {
      adjs = await db.getInvoiceAdjustments(id);
      settlementsTotal = adjs.fold(0.0, (sum, a) => sum + a.amountDelta);
    } catch (_) {}

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
    final sameDayAddsTotal = sameDayAddedItemAdjs.fold(0.0, (sum, a) => sum + (a.price ?? 0.0) * (a.quantity ?? 0.0));
    final itemsTotalForDisplay = includeSameDayOnlyCase ? (itemsTotal + sameDayAddsTotal) : itemsTotal;
    final settlementsTotalForDisplay = includeSameDayOnlyCase ? 0.0 : settlementsTotal;
    final preDiscountTotal = itemsTotalForDisplay + settlementsTotalForDisplay + loadingFee;
    final afterDiscount = ((preDiscountTotal - discount).clamp(0.0, double.infinity)).toDouble();

    final paid = invoice.amountPaidOnInvoice;
    final isCash = invoice.paymentType == 'نقد';
    double settled(String type) => [...adjs, ...sameDayAddedItemAdjs]
        .where((a) => a.settlementPaymentType == type)
        .fold(0.0, (sum, a) => sum + (a.productId != null ? (a.price ?? 0.0) * (a.quantity ?? 0.0) : a.amountDelta));
    final cashSettlements = showSettlementSections ? settled('نقد') : 0.0;
    final debtSettlements = showSettlementSections ? settled('دين') : 0.0;
    final displayedPaid = (isCash && !showSettlementSections) ? afterDiscount : paid + cashSettlements;
    final remainingForPdf = (isCash && !showSettlementSections) ? 0.0 : afterDiscount - displayedPaid;

    // دين العميل: نفس قاعدة الحفظ — الاسم بلا مسافات يحدد الحساب
    double previousDebt = 0.0;
    final customerName = invoice.customerName.trim();
    if (customerName.isNotEmpty) {
      final nameKey = CustomerNameRule.key(customerName);
      for (final c in await db.searchCustomers(customerName)) {
        if (CustomerNameRule.key(c.name.trim()) == nameKey) {
          previousDebt = c.currentTotalDebt;
          break;
        }
      }
    }
    final double currentDebt = showSettlementSections
        ? previousDebt + debtSettlements
        : (isCash ? previousDebt : previousDebt + remainingForPdf);
    final currentDebtForPdf = invoice.status == 'محفوظة' ? previousDebt : currentDebt;
    final invoiceDisplayNumber = invoice.formattedInvoiceNumber;

    final combinedRows = <Map<String, dynamic>>[
      ...filteredItems.map((it) => {'type': 'item', 'item': it}),
      if (includeSameDayOnlyCase) ...sameDayAddedItemAdjs.map((a) => {'type': 'adj', 'adj': a}),
    ];

    // 🎨 تصميم من «مصمم الفاتورة» مختار لهذا النوع؟
    final designed = await InvoiceLayoutStore.activeFor(target);
    if (designed != null) {
      Product? byName(String n) {
        for (final p in allProducts) {
          if (p.name == n) return p;
        }
        return null;
      }

      Product? byId(int? pid) {
        if (pid == null) return null;
        for (final p in allProducts) {
          if (p.id == pid) return p;
        }
        return null;
      }

      final rows = <Map<String, String>>[];
      for (var i = 0; i < combinedRows.length; i++) {
        final r = combinedRows[i];
        if (r['type'] == 'item') {
          final it = r['item'] as InvoiceItem;
          rows.add(DesignedRows.item(i, it, byName(it.productName)));
        } else {
          final a = r['adj'] as InvoiceAdjustment;
          rows.add(DesignedRows.adjustment(i, a, byId(a.productId)));
        }
      }
      final staff = await InvoiceStaff.load(id);
      final created = invoice.createdAt;
      final dateStr = InvoicePrintData.dateText(selectedDate);
      final accountant = (staff?.accountant ?? '').trim().isNotEmpty
          ? staff!.accountant.trim()
          : ((invoice.createdByUsername ?? '').trim().isNotEmpty
              ? await VoucherPrint.displayNameOf(await db.database, invoice.createdByUsername)
              : (AuthService().currentUser?.shownName ?? ''));
      final doc = await LayoutPdfRenderer.render(
        designed,
        InvoicePrintData(
          company: await PrintCompany.load(appSettings),
          fields: {
            'invoiceNo': invoiceDisplayNumber,
            'date': dateStr,
            'time': InvoicePrintData.timeText(created),
            'dateTime': '$dateStr ${InvoicePrintData.timeText(created)}',
            'customer': customerName,
            'phone': (invoice.customerPhone ?? '').trim(),
            'address': (invoice.customerAddress ?? '').trim(),
            'paymentType': invoice.paymentType,
            'user': AuthService().currentUser?.username ?? '',
            'preparer': (staff?.preparer ?? '').trim(),
            'accountant': accountant,
            'copy': '',
          },
          rows: rows,
          totals: {
            'beforeDiscount': preDiscountTotal,
            'discount': discount,
            'afterDiscount': afterDiscount,
            'loadingFee': loadingFee,
            'net': afterDiscount,
            'paid': displayedPaid,
            'remaining': remainingForPdf,
            'previousDebt': previousDebt,
            'currentDebt': currentDebtForPdf,
          },
          paymentType: invoice.paymentType,
        ),
      );
      return doc.save();
    }

    // 🖨️ التصميم الأصلي الموحّد — نفس شعار وخطوط الطباعة من الشاشة
    final logoImage = await LogoService.getLogoImage(appSettings: appSettings);
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    final alnaserFont = pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
    final pdf = pw.Document();
    await PrintedInvoicePdf.addOriginalPages(
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
      invoiceDisplayNumber: invoiceDisplayNumber,
      customerName: invoice.customerName,
      customerAddress: invoice.customerAddress ?? '',
      customerPhone: (invoice.customerPhone ?? '').trim(),
      selectedDate: selectedDate,
      invoiceToManage: invoice,
      preDiscountTotal: preDiscountTotal,
      discount: discount,
      afterDiscount: afterDiscount,
      loadingFee: loadingFee,
      displayedPaidForSettlementsCase: displayedPaid,
      remainingForPdf: remainingForPdf,
      currentDebtForPdf: currentDebtForPdf,
    );
    return pdf.save();
  }
}
