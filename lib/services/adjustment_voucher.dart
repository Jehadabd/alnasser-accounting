// lib/services/adjustment_voucher.dart
//
// 🧾 إشعار مدين / دائن — يُطبع بعد كل إضافة أو إرجاع على فاتورة محفوظة.
//   • إضافة (debit) ⇒ «إشعار مدين»: يزيد المطلوب من العميل.
//   • إرجاع (credit) ⇒ «إشعار دائن»: ينقص المطلوب من العميل.
// التصميم من «مصمم الفاتورة» (نوع الطباعة «إشعار مدين / دائن — A4») أو قالب
// «إشعار رسمي بإطار» إن لم يُختر تصميم. السؤال بعد الحفظ يُطفأ من الإعدادات
// (أو بزر «لا تسألني مرة أخرى»).

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../erp/arabic_words.dart';
import '../invoice_designer/designed_rows.dart';
import '../invoice_designer/invoice_layout_store.dart';
import '../invoice_designer/invoice_layout_templates.dart';
import '../invoice_designer/invoice_print_data.dart';
import '../invoice_designer/layout_pdf_renderer.dart';
import '../models/invoice_adjustment.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'product_codes.dart';
import 'settings_manager.dart';

class AdjustmentVoucher {
  AdjustmentVoucher._();

  static String titleOf(List<InvoiceAdjustment> saved) =>
      (saved.isNotEmpty && saved.first.type == 'credit') ? 'إشعار دائن' : 'إشعار مدين';

  /// بعد حفظ إضافة/إرجاع: يسأل «اطبع الإشعار؟» حسب الإعداد
  static Future<void> afterSave(BuildContext context, {required int invoiceId, required List<InvoiceAdjustment> saved}) async {
    if (saved.isEmpty) return;
    final settings = await SettingsManager.getAppSettings();
    if (settings.adjustmentVoucherMode == 'never' || !context.mounted) return;
    final title = titleOf(saved);
    final amount = saved.fold<double>(0, (s, a) => s + a.amountDelta.abs());
    final choice = settings.adjustmentVoucherMode == 'always'
        ? 'print'
        : await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.receipt_long_rounded, color: title == 'إشعار دائن' ? Colors.red.shade700 : Colors.blue.shade800),
          const SizedBox(width: 8),
          Text('طباعة $title؟'),
        ]),
        content: Text('حُفظ ${title == 'إشعار دائن' ? 'الإرجاع' : 'الإضافة'} بمبلغ ${fmtMoney(amount)} دينار.\n'
            'تطبع سنداً بحجم A4 يوقّعه العميل؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'never'), child: const Text('لا تسألني مرة أخرى')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'no'), child: const Text('لا')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'print'),
            icon: const Icon(Icons.print_rounded),
            label: const Text('طباعة'),
          ),
        ],
      ),
    );
    if (choice == 'never') {
      await SettingsManager.saveAppSettings(settings.copyWith(adjustmentVoucherMode: 'never'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لن يُسأل بعد الآن. لإعادته: الإعدادات ← الفاتورة والطباعة ← إشعار مدين / دائن'),
        ));
      }
      return;
    }
    if (choice != 'print') return;
    try {
      final doc = await build(invoiceId: invoiceId, saved: saved);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat _) async => doc.save(),
        name: '${title}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّرت طباعة $title: $e')));
      }
    }
  }

  /// يبني الإشعار (PDF) لتسويات [saved] المحفوظة للتو على الفاتورة [invoiceId]
  static Future<pw.Document> build({required int invoiceId, required List<InvoiceAdjustment> saved}) async {
    final db = DatabaseService();
    final settings = await SettingsManager.getAppSettings();
    final inv = await db.getInvoiceById(invoiceId);
    if (inv == null) throw StateError('الفاتورة غير موجودة');
    final all = await db.getInvoiceAdjustments(invoiceId);
    final title = titleOf(saved);
    final delta = saved.fold<double>(0, (s, a) => s + a.amountDelta); // بإشارته: + إضافة، − إرجاع
    final amount = delta.abs();

    // أثر السند على الفاتورة: الأصل + كل التسويات (هذه منها)
    final adjTotal = all.fold<double>(0, (s, a) => s + a.amountDelta);
    final invoiceAfter = inv.totalAmount + adjTotal;
    final invoiceBefore = invoiceAfter - delta;

    // حساب العميل: الرصيد الحالي (بعد السند) من الدفتر؛ قبله = بعده − ما أثّر منه على الدين
    double? debtAfter, debtBefore;
    String phone = inv.customerPhone ?? '', address = inv.customerAddress ?? '';
    if (inv.customerId != null) {
      final c = await db.getCustomerById(inv.customerId!);
      if (c != null) {
        debtAfter = c.currentTotalDebt;
        final debtDelta = saved
            .where((a) => (a.settlementPaymentType ?? (inv.paymentType == 'نقد' ? 'نقد' : 'دين')) == 'دين')
            .fold<double>(0, (s, a) => s + a.amountDelta);
        debtBefore = debtAfter - debtDelta;
        if (phone.isEmpty) phone = c.phone ?? '';
        if (address.isEmpty) address = c.address ?? '';
      }
    }

    // البنود
    await ProductCodes.ensureLoaded(); // 🏷️ لعمود «رمز المادة» إن كان في التصميم
    final rows = <Map<String, String>>[];
    for (var i = 0; i < saved.length; i++) {
      final a = saved[i];
      if ((a.productName ?? '').trim().isNotEmpty) {
        final p = a.productId == null ? null : await db.getProductById(a.productId!);
        rows.add(DesignedRows.adjustment(i, a, p)..['amount'] = fmtMoney(a.amountDelta.abs()));
      } else {
        rows.add(DesignedRows.simple(i, a.note?.trim().isNotEmpty == true ? a.note!.trim() : (a.type == 'credit' ? 'إرجاع مبلغ' : 'إضافة مبلغ'),
            1, '', a.amountDelta.abs()));
      }
    }

    final now = DateTime.now();
    final reasons = saved.map((a) => (a.note ?? '').trim()).where((n) => n.isNotEmpty).toSet().join('، ');
    final pay = saved.first.settlementPaymentType ?? inv.paymentType;
    final user = AuthService().currentUser;
    final data = InvoicePrintData(
      company: await PrintCompany.load(settings),
      fields: {
        'voucherTitle': title,
        'voucherNo': '${inv.formattedInvoiceNumber}/${all.length}',
        'voucherReason': reasons.isNotEmpty ? reasons : (title == 'إشعار دائن' ? 'إرجاع على الفاتورة' : 'إضافة على الفاتورة'),
        'invoiceNo': inv.formattedInvoiceNumber,
        'date': InvoicePrintData.dateText(now),
        'time': InvoicePrintData.timeText(now),
        'dateTime': '${InvoicePrintData.dateText(now)} ${InvoicePrintData.timeText(now)}',
        'customer': inv.customerName,
        'phone': phone,
        'address': address,
        'paymentType': pay,
        'user': user?.username ?? '',
        'accountant': user?.shownName ?? '',
        'preparer': '',
        'copy': '',
        'amountWords': ArabicWords.money(amount),
      },
      rows: rows,
      totals: {
        'voucherAmount': amount,
        'invoiceBefore': invoiceBefore,
        'invoiceAfter': invoiceAfter,
        if (debtBefore != null) 'previousDebt': debtBefore,
        if (debtAfter != null) 'currentDebt': debtAfter,
      },
      paymentType: pay,
    );
    final layout = await InvoiceLayoutStore.activeFor(PrintTarget.adjustmentVoucher.key) ?? InvoiceLayoutTemplates.defaultVoucher();
    return LayoutPdfRenderer.render(layout, data);
  }
}
