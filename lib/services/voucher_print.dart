// lib/services/voucher_print.dart
//
// 🧾 طباعة السندات بتصاميم «مصمم السندات»:
//   • سند قبض — تسديد دين (ووصل عدة عملاء)          [receipt]
//   • سند قبض — إضافة على فاتورة نقدية (بالقلم)      [cash_receipt]
//   • سند صرف — مرتجع فاتورة نقدية (بالقلم)          [cash_refund]
//   • إشعار مدين — إضافة على فاتورة آجلة (بالقلم)    [debit_note]
//   • إشعار دائن — مرتجع فاتورة آجلة (بالقلم)        [credit_note]
//
// لكل نوع: التصميم المختار له (أو شكل البرنامج الحالي إن لم يُختر)، وإعداد
// الطباعة بعد الحفظ: اسألني / اطبع دائماً / لا تُظهر.
//
// طباعة فقط — لا يغيّر رصيداً ولا مخزوناً ولا قيداً.
// «المحاسب» في كل سند = من سجّل العملية (لا من يطبعها الآن)؛ ومن يطبع في «طُبع بواسطة».

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite/sqflite.dart';

import '../accounting/ledger.dart';
import '../erp/report_export.dart';
import '../invoice_designer/invoice_layout.dart';
import '../invoice_designer/invoice_layout_store.dart';
import '../invoice_designer/invoice_layout_templates.dart';
import '../invoice_designer/invoice_print_data.dart';
import '../invoice_designer/layout_pdf_renderer.dart';
import 'database_service.dart';
import 'invoice_edit_events.dart';
import 'invoice_edit_log.dart';
import 'invoice_edit_voucher.dart';
import 'printed_vouchers.dart'; // 🧾 سجل السندات المطبوعة ورمز التحقق
import 'settings_manager.dart';

/// أنواع السندات.
class VoucherKinds {
  VoucherKinds._();

  static const receipt = 'receipt';
  static const cashReceipt = InvoiceEditEvents.kindCashReceipt;
  static const cashRefund = InvoiceEditEvents.kindCashRefund;
  static const debitNote = InvoiceEditEvents.kindDebitNote;
  static const creditNote = InvoiceEditEvents.kindCreditNote;

  static const all = [receipt, cashReceipt, cashRefund, debitNote, creditNote];

  static String targetKey(String kind) => 'voucher_$kind';

  static String title(String kind) => switch (kind) {
        receipt => 'سند قبض',
        cashReceipt => 'سند قبض — إضافة على فاتورة',
        cashRefund => 'سند صرف — مرتجع بضاعة',
        debitNote => 'إشعار مدين',
        creditNote => 'إشعار دائن',
        _ => 'سند',
      };

  static String label(String kind) => switch (kind) {
        receipt => 'سند قبض — تسديد دين',
        cashReceipt => 'سند قبض — إضافة على فاتورة نقدية',
        cashRefund => 'سند صرف — مرتجع من فاتورة نقدية',
        debitNote => 'إشعار مدين — إضافة على فاتورة آجلة',
        creditNote => 'إشعار دائن — مرتجع من فاتورة آجلة',
        _ => kind,
      };

  static String hint(String kind) => switch (kind) {
        receipt => 'بعد تسديد دين من سجل الديون، ووصل القبض لعدة عملاء',
        cashReceipt => 'تعديل فاتورة نقدية بالقلم وزاد مجموعها: ما يُقبض من الزبون',
        cashRefund => 'تعديل فاتورة نقدية بالقلم ونقص مجموعها: ما يُرد للزبون',
        debitNote => 'تعديل فاتورة آجلة بالقلم وزاد مجموعها: يزيد دين العميل',
        creditNote => 'تعديل فاتورة آجلة بالقلم ونقص مجموعها: ينقص دين العميل',
        _ => '',
      };

  static IconData icon(String kind) => switch (kind) {
        receipt => Icons.payments_rounded,
        cashReceipt => Icons.add_card_rounded,
        cashRefund => Icons.assignment_return_rounded,
        debitNote => Icons.trending_up_rounded,
        creditNote => Icons.trending_down_rounded,
        _ => Icons.receipt_rounded,
      };

  static Color color(String kind) => switch (kind) {
        receipt => const Color(0xFF047857),
        cashReceipt => const Color(0xFF0E7490),
        cashRefund => const Color(0xFFB45309),
        debitNote => const Color(0xFF1D4ED8),
        creditNote => const Color(0xFFB91C1C),
        _ => const Color(0xFF0F3460),
      };
}

class VoucherPrint {
  VoucherPrint._();

  static final _nf = NumberFormat('#,##0.##', 'en_US');
  static String _m(num v) => _nf.format(v);
  static double _d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);

  // ───────── الإعدادات لكل نوع ─────────

  static String _modeKey(String kind) => 'voucher_print_mode_$kind';

  /// اسألني / اطبع دائماً / لا تُظهر — لكل نوع؛ بلا اختيار ⇒ الإعداد العام في الإعدادات.
  static Future<String> modeFor(String kind) async {
    try {
      final v = await Ledger.getSetting(await DatabaseService().database, _modeKey(kind));
      if (v == 'ask' || v == 'always' || v == 'never') return v!;
    } catch (_) {}
    try {
      final g = (await SettingsManager.getAppSettings()).adjustmentVoucherMode;
      if (g == 'always' || g == 'never') return g;
    } catch (_) {}
    return 'ask';
  }

  static Future<void> setMode(String kind, String mode) async {
    await Ledger.setSetting(await DatabaseService().database, _modeKey(kind), mode);
  }

  /// التصميم المختار لهذا النوع (null ⇒ شكل البرنامج الحالي).
  static Future<InvoiceLayout?> designFor(String kind) => InvoiceLayoutStore.activeFor(VoucherKinds.targetKey(kind));

  /// الاسم الظاهر لمستخدم (أو اسم الدخول نفسه).
  static Future<String> displayNameOf(DatabaseExecutor db, String? username) async {
    final u = (username ?? '').trim();
    if (u.isEmpty) return '';
    try {
      final r = await db.query('users', columns: ['display_name'], where: 'username = ?', whereArgs: [u], limit: 1);
      final n = r.isEmpty ? null : (r.first['display_name'] as String?)?.trim();
      return (n == null || n.isEmpty) ? u : n;
    } catch (_) {
      return u;
    }
  }

  static Future<Uint8List> _render(InvoiceLayout layout, InvoicePrintData data) async =>
      (await renderVoucher(layout, data)).save();

  /// هل في التصميم عنصر يعرض [key] (حقل، بند مربع، أو {key} في نص)؟
  static bool _uses(InvoiceLayout l, String key) => l.elements.any((e) =>
      (e.type == ElType.field && e.s('key', '') == key) ||
      (e.type == ElType.totals && e.strings('items').contains(key)) ||
      (e.type == ElType.text && e.s('text', '').contains('{$key}')));

  /// 🔢 رقم السند يُطبع دائماً: إن لم يكن في التصميم عنصر له، يُلحق بعنوان السند
  /// («سند قبض رقم 12»)، وإن لم يكن فيه عنوان أيضاً يُضاف سطر «رقم السند» أسفل الورقة.
  static Future<pw.Document> renderVoucher(InvoiceLayout layout, InvoicePrintData data) {
    var l = layout;
    var d = data;
    var copied = false;
    final no = data.field('voucherNo').trim();
    // 🔐 رمز التحقق (ورقم النسخة) يُطبع دائماً: إن لم يضعه التصميم يُضاف أسفل يسار الورقة
    final code = data.field('verifyCode').trim();
    if (code.isNotEmpty && !_uses(l, 'verifyCode')) {
      l = layout.copy();
      copied = true;
      l.elements.add(LayoutElement(
        id: InvoiceLayout.newId('e'),
        type: ElType.field,
        x: 8,
        y: l.heightMm - 10,
        w: 80,
        h: 7,
        props: {'key': 'verifyCode', 'label': 'رمز التحقق', 'fontSize': 10.0, 'bold': true, 'align': 'left'},
      ));
    }
    if (no.isNotEmpty && !_uses(l, 'voucherNo')) {
      if (_uses(l, 'voucherTitle')) {
        // نسخة من البيانات (لا تُعدَّل الأصلية: المعاينة تعيد استعمالها)
        d = InvoicePrintData(
          company: data.company,
          fields: {...data.fields, 'voucherTitle': '${data.field('voucherTitle')} رقم $no'},
          rows: data.rows,
          totals: data.totals,
          paymentType: data.paymentType,
        );
      } else {
        if (!copied) l = layout.copy();
        l.elements.add(LayoutElement(
          id: InvoiceLayout.newId('e'),
          type: ElType.field,
          x: l.widthMm - 70,
          y: l.heightMm - 10,
          w: 62,
          h: 7,
          props: {'key': 'voucherNo', 'label': 'رقم السند', 'fontSize': 11.0, 'bold': true, 'align': 'right'},
        ));
      }
    }
    return LayoutPdfRenderer.render(l, d);
  }

  // ═══════════════════════ سند قبض — تسديد دين ═══════════════════════

  /// PDF وصل القبض بالتصميم المختار، أو null إن لم يُختر تصميم (يُطبع الشكل الحالي).
  /// [lines]: customer_name, amount, discount, balance_before, balance_after (كما في ReceiptPdf).
  static Future<Uint8List?> receiptPdf({
    required int number,
    required DateTime date,
    required List<Map<String, Object?>> lines,
    String boxName = '',
    String? docNo,
    String? notes,
    String? recordedBy,
    String? phone,
    PrintStamp? stamp,
  }) async {
    final layout = await designFor(VoucherKinds.receipt);
    if (layout == null) return null;
    return _render(
        layout,
        await receiptData(
            number: number,
            date: date,
            lines: lines,
            boxName: boxName,
            docNo: docNo,
            notes: notes,
            recordedBy: recordedBy,
            phone: phone,
            stamp: stamp));
  }

  /// بيانات سند القبض للتصميم (يستعملها أيضاً سند القبض القديم من صفحة العميل).
  static Future<InvoicePrintData> receiptData({
    required int number,
    required DateTime date,
    required List<Map<String, Object?>> lines,
    String boxName = '',
    String? docNo,
    String? notes,
    String? recordedBy,
    String? phone,
    PrintStamp? stamp,
  }) async {
    final db = await DatabaseService().database;
    final total = lines.fold<double>(0, (s, l) => s + _d(l['amount']));
    final disc = lines.fold<double>(0, (s, l) => s + _d(l['discount']));
    final single = lines.length == 1 ? lines.first : null;
    final dateStr = InvoicePrintData.dateText(date);
    final data = InvoicePrintData(
      company: await PrintCompany.load(),
      fields: {
        'voucherTitle': VoucherKinds.title(VoucherKinds.receipt),
        'voucherNo': '$number',
        'invoiceNo': '$number',
        'date': dateStr,
        'time': InvoicePrintData.timeText(date),
        'dateTime': '$dateStr ${InvoicePrintData.timeText(date)}',
        'customer': single == null ? 'عدة عملاء (${lines.length})' : '${single['customer_name'] ?? ''}',
        'phone': phone ?? '',
        'boxName': boxName,
        'docNo': docNo ?? '',
        'voucherReason': (notes ?? '').trim().isEmpty ? 'تسديد دين' : notes!.trim(),
        'paymentType': 'نقد',
        'user': recordedBy ?? '',
        'accountant': await displayNameOf(db, recordedBy),
        if (stamp != null) 'verifyCode': stamp.line,
      },
      rows: [
        for (var i = 0; i < lines.length; i++)
          {
            'serial': '${i + 1}',
            'details': '${lines[i]['customer_name'] ?? ''}',
            'quantity': '',
            'qty': '',
            'unit': '',
            'price': _m(_d(lines[i]['balance_before'])),
            'discount': _d(lines[i]['discount']) > 0 ? _m(_d(lines[i]['discount'])) : '',
            'priceBeforeDiscount': _m(_d(lines[i]['balance_before'])),
            'amount': _m(_d(lines[i]['amount'])),
            'blank': _m(_d(lines[i]['balance_after'])),
          },
      ],
      totals: {
        'voucherAmount': total,
        'net': total,
        'paid': total,
        if (disc > 0) 'discount': disc,
        if (single != null) 'previousDebt': _d(single['balance_before']),
        if (single != null) 'currentDebt': _d(single['balance_after']),
      },
    );
    return data;
  }

  /// بعد تسديد: يطبع حسب إعداد «سند قبض» (اسألني / دائماً / لا).
  /// [build] يبني PDF الشكل الحالي إن لم يُختر تصميم.
  static Future<void> offerReceipt(
    BuildContext context, {
    required int number,
    required Future<Uint8List?> Function() designed,
    required Future<Uint8List> Function() legacy,
  }) async {
    final mode = await modeFor(VoucherKinds.receipt);
    if (mode == 'never' || !context.mounted) return;
    if (mode == 'ask') {
      final ok = await _ask(context, VoucherKinds.receipt, 'هل تريد طباعة سند القبض رقم $number؟');
      if (ok != true || !context.mounted) return;
    }
    final bytes = await designed() ?? await legacy();
    if (context.mounted) await ReportExport.openPdf(context, bytes, 'سند_قبض_$number');
  }

  static Future<bool?> _ask(BuildContext context, String kind, String message) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            Icon(VoucherKinds.icon(kind), color: VoucherKinds.color(kind)),
            const SizedBox(width: 8),
            Expanded(child: Text(VoucherKinds.title(kind))),
          ]),
          content: Text(message, style: const TextStyle(height: 1.6)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لاحقاً')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: VoucherKinds.color(kind)),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.print_rounded),
              label: const Text('طباعة'),
            ),
          ],
        ),
      );

  // ═══════════════════════ تعديل بالقلم (قبض/صرف/مدين/دائن) ═══════════════════════

  /// بيانات طباعة حدث تعديل. null إن لم يوجد الحدث أو لا فرق في مجموعه.
  static Future<(String, InvoicePrintData)?> editEventData(int eventId) async {
    final db = await DatabaseService().database;
    final e = await InvoiceEditEvents.byId(db, eventId);
    if (e == null) return null;
    final kind = e['doc_kind'] as String?;
    if (kind == null) return null;
    final invId = (e['invoice_id'] as num).toInt();
    final inv = await db.query('invoices', where: 'id = ?', whereArgs: [invId], limit: 1);
    if (inv.isEmpty) return null;
    final i = inv.first;
    final tb = _d(e['total_before']);
    final ta = _d(e['total_after']);
    final amount = (ta - tb).abs();
    final when = DateTime.tryParse('${e['event_date']}') ?? DateTime.now();
    final dateStr = InvoicePrintData.dateText(when);
    final n = (i['invoice_number'] as String?)?.trim();
    final invNo = (n != null && n.isNotEmpty) ? n : '$invId';

    // المواد التي تغيّرت في هذا الحفظ (من سجل التعديل)
    List<Map<String, Object?>> changes = const [];
    if (e['edited_at'] != null) {
      try {
        changes = await db.query('invoice_edit_changes',
            where: 'invoice_id = ? AND edited_at = ?', whereArgs: [invId, e['edited_at']], orderBy: 'id');
      } catch (_) {}
    }
    final rows = <Map<String, String>>[];
    for (final c in changes) {
      final dq = (_d(c['qty_after']) - _d(c['qty_before'])).abs();
      final da = (_d(c['amount_after']) - _d(c['amount_before'])).abs();
      final unit = '${c['unit'] ?? ''}'.trim();
      final kindLabel = '${c['kind'] ?? ''}' == InvoiceEditLog.kindPrice ? 'تعديل سعر' : '${c['kind'] ?? ''}';
      rows.add({
        'serial': '${rows.length + 1}',
        'details': '${c['product_name'] ?? ''}${kindLabel.isEmpty ? '' : ' — $kindLabel'}',
        'quantity': dq > 0 ? '${_m(dq)} $unit'.trim() : '',
        'qty': dq > 0 ? _m(dq) : '',
        'unit': unit,
        'price': dq > 0 ? _m(da / dq) : '',
        'amount': _m(da),
        'blank': kindLabel,
      });
    }

    // حساب العميل (للآجلة): الرصيد بعد السند = مجموع حركاته حتى لحظة الحدث
    double? debtAfter, debtBefore;
    final cid = (i['customer_id'] as num?)?.toInt();
    if (cid != null && (kind == VoucherKinds.debitNote || kind == VoucherKinds.creditNote)) {
      try {
        final r = await db.rawQuery('''
          SELECT COALESCE(SUM(amount_changed), 0) AS s FROM transactions
          WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0 AND transaction_date <= ?''', [cid, e['event_date']]);
        debtAfter = _d(r.first['s']);
        final dDebt = (ta - _d(e['paid_after'])) - (tb - _d(e['paid_before']));
        debtBefore = debtAfter - dDebt;
      } catch (_) {}
    }

    final recordedBy = e['created_by'] as String?;
    final data = InvoicePrintData(
      company: await PrintCompany.load(),
      fields: {
        'voucherTitle': VoucherKinds.title(kind),
        'voucherNo': '${e['doc_no'] ?? eventId}',
        'invoiceNo': invNo,
        'date': dateStr,
        'time': InvoicePrintData.timeText(when),
        'dateTime': '$dateStr ${InvoicePrintData.timeText(when)}',
        'customer': '${i['customer_name'] ?? ''}',
        'phone': '${i['customer_phone'] ?? ''}',
        'address': '${i['customer_address'] ?? ''}',
        'paymentType': '${i['payment_type'] ?? ''}',
        'voucherReason': ((e['summary'] as String?) ?? '').trim().isEmpty
            ? 'تعديل على الفاتورة رقم $invNo'
            : 'تعديل على الفاتورة رقم $invNo: ${e['summary']}',
        'user': recordedBy ?? '',
        'accountant': await displayNameOf(db, recordedBy),
      },
      rows: rows,
      totals: {
        'voucherAmount': amount,
        'net': amount,
        'invoiceBefore': tb,
        'invoiceAfter': ta,
        if (debtBefore != null) 'previousDebt': debtBefore,
        if (debtAfter != null) 'currentDebt': debtAfter,
      },
      paymentType: '${i['payment_type'] ?? ''}',
    );
    return (kind, data);
  }

  /// بعد حفظ تعديل بالقلم: سند النوع المناسب حسب إعداده.
  /// [legacyCashVoucherId]: سند الفاتورة النقدية القديم (شكل البرنامج الحالي إن لم يُختر تصميم).
  static Future<void> offerEditEvent(BuildContext context, int eventId, {int? legacyCashVoucherId}) async {
    final r = await editEventData(eventId);
    if (r == null || !context.mounted) return;
    final (kind, data) = r;
    final mode = await modeFor(kind);
    if (mode == 'never' || !context.mounted) return;
    if (mode == 'ask') {
      final ok = await _ask(
          context,
          kind,
          '${VoucherKinds.title(kind)} رقم ${data.field('voucherNo')}\n'
          'المبلغ: ${_m(data.totals['voucherAmount'] ?? 0)} دينار — الفاتورة ${data.field('invoiceNo')}\n'
          'مجموعها من ${_m(data.totals['invoiceBefore'] ?? 0)} إلى ${_m(data.totals['invoiceAfter'] ?? 0)}');
      if (ok != true || !context.mounted) return;
    }
    await printEditEvent(context, eventId, legacyCashVoucherId: legacyCashVoucherId, prepared: r);
  }

  /// يطبع سند حدث تعديل (التصميم المختار، أو الشكل الحالي).
  static Future<void> printEditEvent(BuildContext context, int eventId,
      {int? legacyCashVoucherId, (String, InvoicePrintData)? prepared}) async {
    final r = prepared ?? await editEventData(eventId);
    if (r == null) return;
    final (kind, raw) = r;
    // 🧾 سجل السندات المطبوعة: يُسجَّل قبل الطباعة؛ فشله يوقفها (ورقة بلا سجل لا يُتحقق منها)
    final PrintStamp stamp;
    try {
      final db = await DatabaseService().database;
      final e = await InvoiceEditEvents.byId(db, eventId);
      final invId = (e?['invoice_id'] as num?)?.toInt() ?? 0;
      final inv = invId == 0
          ? const <Map<String, Object?>>[]
          : await db.query('invoices', columns: ['customer_id'], where: 'id = ?', whereArgs: [invId], limit: 1);
      stamp = await PrintedVouchers.forEditEvent(
        eventId: eventId,
        kind: kind,
        voucherNo: raw.field('voucherNo'),
        amount: raw.totals['voucherAmount'] ?? 0,
        customerName: raw.field('customer'),
        customerId: inv.isEmpty ? null : (inv.first['customer_id'] as num?)?.toInt(),
        invoiceId: invId,
        invoiceNo: raw.field('invoiceNo'),
        details: {
          'invoice_before': raw.totals['invoiceBefore'],
          'invoice_after': raw.totals['invoiceAfter'],
          'debt_before': raw.totals['previousDebt'],
          'debt_after': raw.totals['currentDebt'],
          'reason': raw.field('voucherReason'),
          'recorded_by': raw.field('user'),
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('لم يُطبع السند: تعذّر تسجيله في سجل السندات المطبوعة ($e)'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }
    final data = InvoicePrintData(
      company: raw.company,
      fields: {...raw.fields, 'verifyCode': stamp.line},
      rows: raw.rows,
      totals: raw.totals,
      paymentType: raw.paymentType,
    );
    final layout = await designFor(kind);
    Uint8List? bytes;
    if (layout != null) {
      bytes = await _render(layout, data);
    } else if ((kind == VoucherKinds.cashReceipt || kind == VoucherKinds.cashRefund) && legacyCashVoucherId != null) {
      // الشكل الحالي للسند النقدي
      bytes = await InvoiceEditVoucher.buildPdf(legacyCashVoucherId, number: data.field('voucherNo'), stampLine: stamp.line);
    }
    // بلا تصميم ولا سند قديم: قالب البرنامج الافتراضي لهذا النوع
    bytes ??= await _render(InvoiceLayoutTemplates.defaultFor(kind), data);
    if (context.mounted) {
      await ReportExport.openPdf(context, bytes, '${VoucherKinds.title(kind)}_${data.field('voucherNo')}');
    }
  }
}
