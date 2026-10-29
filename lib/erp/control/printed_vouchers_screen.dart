// lib/erp/control/printed_vouchers_screen.dart
//
// 🧾 سجل السندات المطبوعة — ثلاث طرق للفتح، والشاشة واحدة:
//   • من العميل (سجل الديون ← العميل ← ⋮): كل سندات العميل — تسديد الدين، سندات الفواتير
//     النقدية (قبض/صرف)، الإشعارات المدينة والدائنة، والأرشيف القديم.
//   • من سجل تعديلات الفاتورة: سندات هذه الفاتورة فقط.
//   • من المحاسبة/الرقابة: كل السندات + التحقق برقم السند أو رمز التحقق المطبوع عليه.
// لكل سند: كم مرة طُبع، من طبعه ومتى، رمز التحقق، وحال العملية الآن (سليمة، تغيّر مبلغها،
// حُذفت، عُدّلت الفاتورة بعده). إعادة الطباعة تُسجَّل نسخة جديدة («نسخة 2»).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import '../../accounting/screens/acc_ui.dart' show fmtMoney, fmtDate, showError;
import '../../services/logo_service.dart';
import '../../services/printed_vouchers.dart';
import '../../services/receipt_voucher_pdf_service.dart';
import '../../services/voucher_print.dart';
import '../debts/receipt_pdf.dart';
import '../debts/receipts_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../report_export.dart';
import 'control_common.dart';

String _dt(DateTime d) =>
    '${fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

IconData _icon(String kind) =>
    kind == PrintedVoucherKind.legacyReceipt ? Icons.archive_rounded : VoucherKinds.icon(kind);

Color _color(String kind) =>
    kind == PrintedVoucherKind.legacyReceipt ? ErpColors.muted : VoucherKinds.color(kind);

class PrintedVouchersScreen extends StatefulWidget {
  const PrintedVouchersScreen({super.key, this.customerId, this.customerName, this.invoiceId, this.invoiceLabel});
  final int? customerId;
  final String? customerName;
  final int? invoiceId;
  final String? invoiceLabel;

  @override
  State<PrintedVouchersScreen> createState() => _PrintedVouchersScreenState();
}

class _PrintedVouchersScreenState extends State<PrintedVouchersScreen> {
  String _q = '';
  String? _kind;
  List<PrintedVoucher> _rows = const [];
  List<Map<String, Object?>> _legacy = const [];
  bool _loading = true;

  bool get _global => widget.customerId == null && widget.invoiceId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await PrintedVouchers.list(customerId: widget.customerId, invoiceId: widget.invoiceId, query: _q);
      var legacy = const <Map<String, Object?>>[];
      if (widget.invoiceId == null && (!_global || _q.trim().isNotEmpty)) {
        final reg = {for (final r in rows) if (r.refType == PrintedRef.legacyReceipt) r.refId};
        legacy = [
          for (final l in await PrintedVouchers.legacyArchive(customerId: widget.customerId, query: _q))
            if (!reg.contains(l['id'])) l
        ];
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _legacy = legacy;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  String get _title {
    if (widget.invoiceId != null) return 'سندات الفاتورة ${widget.invoiceLabel ?? '#${widget.invoiceId}'}';
    if (widget.customerId != null) return 'السندات المطبوعة — ${widget.customerName ?? ''}';
    return 'سجل السندات المطبوعة';
  }

  // ───────────────────────── إعادة الطباعة ─────────────────────────

  Future<void> _reprint(PrintedVoucher v) async {
    try {
      switch (v.refType) {
        case PrintedRef.customerReceipt:
          await _reprintReceipt(v.refId!);
        case PrintedRef.editEvent:
          await VoucherPrint.printEditEvent(context, v.refId!);
        case PrintedRef.legacyReceipt:
          final db = await controlDb();
          final r = await db.query('customer_receipt_vouchers', where: 'id = ?', whereArgs: [v.refId], limit: 1);
          if (r.isEmpty) throw ErpException('السند غير موجود في الأرشيف القديم');
          await _reprintLegacy(r.first);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    _load();
  }

  Future<void> _reprintReceipt(int receiptId) async {
    final db = await controlDb();
    final h = await db.rawQuery('''
      SELECT r.*, b.name AS box_name FROM customer_receipts r LEFT JOIN cash_boxes b ON b.id = r.cash_box_id
      WHERE r.id = ?''', [receiptId]);
    if (h.isEmpty) throw ErpException('الوصل غير موجود — حُذف بعد طباعته');
    final r = h.first;
    final lines = await ReceiptsService().receiptLines(receiptId);
    final stamp = await PrintedVouchers.forCustomerReceipt(receiptId);
    final bytes = await ReceiptPdf.build(
      title: 'وصل قبض',
      number: r['receipt_no'] as int,
      date: parseDate(r['receipt_date']),
      boxName: '${r['box_name'] ?? ''}',
      currency: (r['currency'] as String?) ?? 'IQD',
      fxRate: d0(r['fx_rate']),
      lines: lines,
      docNo: r['doc_no'] as String?,
      notes: r['notes'] as String?,
      commission: d0(r['commission']),
      recordedBy: r['created_by'] as String?,
      stamp: stamp,
    );
    if (mounted) await ReportExport.openPdf(context, bytes, 'وصل_قبض_${r['receipt_no']}_نسخة_${stamp.copyNo}');
  }

  Future<void> _reprintLegacy(Map<String, Object?> r) async {
    final stamp = await PrintedVouchers.forLegacyReceipt(
      archiveId: r['id'] as int,
      receiptNumber: (r['receipt_number'] as num).toInt(),
      customerId: (r['customer_id'] as num).toInt(),
      customerName: '${r['customer_name'] ?? ''}',
      paid: d0(r['paid_amount']),
      before: d0(r['before_payment']),
      after: d0(r['after_payment']),
    );
    String? recordedBy;
    if (r['transaction_id'] != null) {
      try {
        final db = await controlDb();
        final tr = await db.query('transactions',
            columns: ['created_by_username'], where: 'id = ?', whereArgs: [r['transaction_id']], limit: 1);
        recordedBy = tr.isEmpty ? null : tr.first['created_by_username'] as String?;
      } catch (_) {}
    }
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    final brand = pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
    final logo = await LogoService.getLogoImage();
    final pdf = await ReceiptVoucherPdfService.generateReceiptVoucherPdf(
      recordedBy: recordedBy,
      customerName: '${r['customer_name'] ?? ''}',
      beforePayment: d0(r['before_payment']),
      paidAmount: d0(r['paid_amount']),
      afterPayment: d0(r['after_payment']),
      dateTime: parseDate(r['created_at']),
      font: font,
      alnaserFont: brand,
      logoImage: logo,
      receiptNumber: (r['receipt_number'] as num).toInt(),
      stamp: stamp,
    );
    final bytes = await pdf.save();
    if (mounted) await ReportExport.openPdf(context, bytes, 'سند_قبض_${r['receipt_number']}_نسخة_${stamp.copyNo}');
  }

  // ───────────────────────── التفاصيل والتحقق ─────────────────────────

  Future<void> _details(PrintedVoucher v) async {
    final prints = await PrintedVouchers.printsOf(v);
    final (state, stateText) = await PrintedVouchers.stateOf(v);
    if (!mounted) return;
    final stateColor = switch (state) {
      VoucherState.ok => ErpColors.green,
      VoucherState.laterEdit => ErpColors.orange,
      VoucherState.changed || VoucherState.deleted => ErpColors.red,
      VoucherState.unknown => ErpColors.muted,
    };
    final d = v.details;
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(_icon(v.kind), color: _color(v.kind)),
          const SizedBox(width: 8),
          Expanded(child: Text('${PrintedVoucherKind.label(v.kind)} رقم ${v.voucherNo}', style: const TextStyle(fontSize: 16))),
        ]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: stateColor.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Icon(state == VoucherState.ok ? Icons.verified_rounded : Icons.report_problem_rounded, color: stateColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(stateText, style: TextStyle(color: stateColor, fontWeight: FontWeight.w700))),
                ]),
              ),
              const SizedBox(height: 10),
              Text('قارن هذه البيانات بالورقة التي بين يديك:', style: const TextStyle(color: ErpColors.muted, fontSize: 12.5)),
              const SizedBox(height: 6),
              _kv('المبلغ', '${fmtMoney(v.amount)} دينار'),
              _kv('العميل', v.customerName),
              if (v.invoiceNo != null) _kv('الفاتورة', v.invoiceNo!),
              if (v.code.isNotEmpty) _kv('رمز التحقق', v.code),
              if (d['date'] != null) _kv('تاريخ الوصل', fmtDate(parseDate(d['date']))),
              if (d['invoice_before'] != null && d['invoice_after'] != null)
                _kv('مجموع الفاتورة', '${fmtMoney(d0(d['invoice_before']))} ← ${fmtMoney(d0(d['invoice_after']))}'),
              if (d['debt_before'] != null && d['debt_after'] != null)
                _kv('رصيد العميل', '${fmtMoney(d0(d['debt_before']))} ← ${fmtMoney(d0(d['debt_after']))}'),
              if (d['before'] != null && d['after'] != null)
                _kv('الرصيد', '${fmtMoney(d0(d['before']))} ← ${fmtMoney(d0(d['after']))}'),
              if ((d['recorded_by'] ?? '').toString().isNotEmpty) _kv('سجّل العملية', '${d['recorded_by']}'),
              const Divider(height: 20),
              Text('الطباعات (${prints.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final p in prints)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 14, child: Text('${p.copyNo}', style: const TextStyle(fontSize: 12))),
                  title: Text(p.copyNo == 1 ? 'النسخة الأولى' : 'نسخة ${p.copyNo}'),
                  subtitle: Text('${_dt(p.printedAt)} — ${p.printedBy}'
                      '${(p.amount - v.amount).abs() >= 0.5 ? ' — بمبلغ ${fmtMoney(p.amount)}' : ''}'),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إغلاق')),
          if (state != VoucherState.deleted)
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.print_rounded),
              label: Text('إعادة الطباعة (نسخة ${prints.length + 1})'),
            ),
        ],
      ),
    );
    if (again == true) await _reprint(v);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: ErpColors.muted))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  Future<void> _legacyTap(Map<String, Object?> r) async {
    final ok = await confirmDialog(
      context,
      'سند قبض رقم ${r['receipt_number']} — الأرشيف القديم',
      'المبلغ ${fmtMoney(d0(r['paid_amount']))} — ${r['customer_name'] ?? ''}\n'
          'طُبع في ${_dt(parseDate(r['created_at']))}\n'
          'الرصيد ${fmtMoney(d0(r['before_payment']))} ← ${fmtMoney(d0(r['after_payment']))}\n\n'
          'طُبع قبل سجل السندات: بلا رمز تحقق. إعادة طباعته تسجّله نسخة جديدة برمز.',
      ok: 'إعادة الطباعة',
    );
    if (!ok) return;
    try {
      await _reprintLegacy(r);
    } catch (e) {
      if (mounted) showError(context, e);
    }
    _load();
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final kinds = <String?>[
      null,
      PrintedVoucherKind.receipt,
      PrintedVoucherKind.cashReceipt,
      PrintedVoucherKind.cashRefund,
      PrintedVoucherKind.debitNote,
      PrintedVoucherKind.creditNote,
      if (widget.invoiceId == null) PrintedVoucherKind.legacyReceipt,
    ];
    final shown = _kind == null ? _rows : _rows.where((r) => r.kind == _kind).toList();
    final legacyShown = (_kind == null || _kind == PrintedVoucherKind.legacyReceipt) ? _legacy : const <Map<String, Object?>>[];
    return ErpPage(
      title: _title,
      subtitle: 'ما طُبع فقط — مع من طبعه ومتى ورمز التحقق',
      icon: Icons.verified_user_rounded,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      headerExtra: SearchBox(
        autofocus: _global,
        hint: _global ? 'تحقق من ورقة: اكتب رقم السند أو رمز التحقق المطبوع عليها' : 'بحث: رقم السند، رمز التحقق، الاسم',
        onChanged: (v) {
          _q = v;
          _load();
        },
      ),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
            for (final k in kinds)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(
                  label: Text(k == null ? 'الكل' : PrintedVoucherKind.label(k)),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty && legacyShown.isEmpty
                  ? EmptyState(
                      _global && _q.trim().isNotEmpty
                          ? 'لا يوجد سند مطبوع بهذا الرقم أو الرمز.\nإن كانت الورقة تحمل رمز تحقق ولم يُعثر عليه فهي ليست من طباعتنا.'
                          : 'لا سندات مطبوعة بعد',
                      icon: _global && _q.trim().isNotEmpty ? Icons.gpp_bad_rounded : Icons.receipt_long_rounded)
                  : ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 24), children: [
                      for (final v in shown)
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                          child: ListTile(
                            onTap: () => _details(v),
                            leading: CircleAvatar(
                              backgroundColor: _color(v.kind).withValues(alpha: 0.12),
                              child: Icon(_icon(v.kind), color: _color(v.kind), size: 20),
                            ),
                            title: Text('${PrintedVoucherKind.label(v.kind)} رقم ${v.voucherNo} — ${fmtMoney(v.amount)}',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([
                              v.customerName,
                              if (v.invoiceNo != null) 'فاتورة ${v.invoiceNo}',
                              'آخر طباعة ${_dt(v.printedAt)} — ${v.printedBy}',
                              if (v.code.isNotEmpty) 'رمز ${v.code}',
                            ].where((x) => x.isNotEmpty).join(' • ')),
                            trailing: StatusBadge(v.copies > 1 ? '${v.copies} نسخ' : 'نسخة واحدة',
                                color: v.copies > 1 ? ErpColors.orange : ErpColors.green),
                          ),
                        ),
                      if (legacyShown.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(8, 14, 8, 6),
                          child: Text('الأرشيف القديم (طُبع قبل سجل السندات — بلا رمز تحقق)',
                              style: TextStyle(fontWeight: FontWeight.bold, color: ErpColors.muted)),
                        ),
                        for (final r in legacyShown)
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                            child: ListTile(
                              onTap: () => _legacyTap(r),
                              leading: const CircleAvatar(
                                backgroundColor: Color(0x14000000),
                                child: Icon(Icons.archive_rounded, color: ErpColors.muted, size: 20),
                              ),
                              title: Text('سند قبض رقم ${r['receipt_number']} — ${fmtMoney(d0(r['paid_amount']))}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('${r['customer_name'] ?? ''} • ${_dt(parseDate(r['created_at']))}'),
                            ),
                          ),
                      ],
                    ]),
        ),
      ]),
    );
  }
}
