// screens/invoice_details_screen.dart
//
// 🧾 تفصيل فاتورة من التقارير (قراءة فقط): الرأس، البنود بكلفتها وربحها،
// التسويات بعد الحفظ، والملخص (البنود − الخصم + التحميل = المجموع، المدفوع،
// المتبقي، الكلفة، الربح). الأرقام من المحرك الموحّد فتطابق تقارير الشهر.

import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../models/invoice_adjustment.dart';
import '../services/database_service.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';

class InvoiceDetailsScreen extends StatefulWidget {
  final int invoiceId;

  const InvoiceDetailsScreen({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  Invoice? _invoice;
  SalesInvoiceFact? _fact;
  List<InvoiceAdjustment> _adjustments = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvoiceDetails();
  }

  Future<void> _loadInvoiceDetails() async {
    setState(() => _isLoading = true);
    try {
      final invoice = await _databaseService.getInvoiceById(widget.invoiceId);
      final facts = await ReportsService().loadFacts(invoiceId: widget.invoiceId);
      List<InvoiceAdjustment> adj = const [];
      try {
        adj = await _databaseService.getInvoiceAdjustments(widget.invoiceId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _fact = facts.invoices.isEmpty ? null : facts.invoices.first;
        _adjustments = adj;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      setToast(context, 'حدث خطأ في تحميل الفاتورة: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;
    final f = _fact;
    final profit = repCanSeeProfit();
    return ReportScaffold(
      title: inv == null ? 'فاتورة' : 'فاتورة ${inv.formattedInvoiceNumber}',
      subtitle: inv == null ? null : '${inv.customerName} • ${repDate(inv.invoiceDate)}',
      icon: Icons.receipt_long_rounded,
      maxWidth: 980,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _loadInvoiceDetails, icon: const Icon(Icons.refresh_rounded))],
      loading: _isLoading,
      children: _isLoading
          ? null
          : inv == null
              ? const [EmptyReport(title: 'الفاتورة غير موجودة', text: 'ربما حُذفت.', icon: Icons.receipt_long_outlined)]
              : [
                  _header(inv),
                  if (f == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: SetBanner('هذه الفاتورة ليست «محفوظة» (معلّقة أو محذوفة)، فلا تدخل في التقارير.',
                          kind: SetBannerKind.warn),
                    ),
                  _itemsCard(inv, f, profit),
                  if (_adjustments.isNotEmpty) _adjustmentsCard(),
                  _summaryCard(inv, f, profit),
                ],
    );
  }

  Widget _header(Invoice inv) {
    final cash = inv.paymentType == 'نقد';
    Widget info(IconData i, String label, String value) => SizedBox(
          width: 220,
          child: Row(children: [
            Icon(i, size: 18, color: kSetMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 11.5, color: kSetMuted)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
              ]),
            ),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kSetBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cash ? kSetGreen : kSetOrange,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(cash ? Icons.payments_rounded : Icons.schedule_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('فاتورة ${inv.formattedInvoiceNumber}',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kSetText)),
              Text('${inv.paymentType} • ${inv.status}', style: const TextStyle(color: kSetMuted)),
            ]),
          ),
          MoneyLabel(inv.totalAmount, size: 22),
        ]),
        const Divider(height: 24),
        Wrap(spacing: 16, runSpacing: 12, children: [
          info(Icons.person_rounded, 'العميل', inv.customerName),
          if ((inv.customerPhone ?? '').isNotEmpty) info(Icons.phone_rounded, 'الهاتف', inv.customerPhone!),
          info(Icons.event_rounded, 'التاريخ', '${repDate(inv.invoiceDate)}  ${inv.invoiceDate.hour.toString().padLeft(2, '0')}:${inv.invoiceDate.minute.toString().padLeft(2, '0')}'),
          if ((inv.createdByUsername ?? '').isNotEmpty) info(Icons.badge_rounded, 'أنشأها', inv.createdByUsername!),
          if ((inv.installerName ?? '').isNotEmpty) info(Icons.engineering_rounded, 'الفني', inv.installerName!),
          if ((inv.customerAddress ?? '').isNotEmpty) info(Icons.location_on_rounded, 'العنوان', inv.customerAddress!),
        ]),
        if ((inv.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          SetBanner(inv.notes!.trim(), icon: Icons.sticky_note_2_outlined),
        ],
      ]),
    );
  }

  Widget _itemsCard(Invoice inv, SalesInvoiceFact? f, bool profit) {
    final items = f?.items.where((i) => i.kind == SalesItemKind.sale).toList() ?? const <SalesItemFact>[];
    return SetCard(
      title: 'البنود',
      subtitle: '${items.length} صنف',
      icon: Icons.list_alt_rounded,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: items.isEmpty
          ? const EmptyReport(title: 'لا بنود', icon: Icons.inbox_outlined)
          : Column(children: [
              _ItemHeader(showProfit: profit),
              for (var i = 0; i < items.length; i++) _ItemRow(n: i + 1, it: items[i], showProfit: profit, zebra: i.isOdd),
            ]),
    );
  }

  Widget _adjustmentsCard() {
    return SetCard(
      title: 'تعديلات بعد الحفظ',
      subtitle: 'تسويات غيّرت مجموع الفاتورة',
      icon: Icons.edit_note_rounded,
      color: kRepPurple,
      child: Column(children: [
        for (final a in _adjustments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(a.amountDelta >= 0 ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                  color: a.amountDelta >= 0 ? kSetOrange : kSetGreen, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    a.productName != null && a.productName!.isNotEmpty
                        ? '${a.productName} — ${repQty(a.quantity ?? 0)} ${a.saleType ?? a.unit ?? ''}'
                        : (a.type == 'credit' ? 'تنزيل من الفاتورة' : 'إضافة على الفاتورة'),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText),
                  ),
                  Text(
                    [repDate(a.createdAt), if ((a.note ?? '').isNotEmpty) a.note!, if ((a.settlementPaymentType ?? '').isNotEmpty) a.settlementPaymentType!]
                        .join(' • '),
                    style: const TextStyle(fontSize: 12, color: kSetMuted),
                  ),
                ]),
              ),
              MoneyLabel(a.amountDelta),
            ]),
          ),
      ]),
    );
  }

  double _unexplained(Invoice inv, double gross) =>
      inv.totalAmount - (gross - inv.discount + inv.loadingFee + _adjustments.fold<double>(0, (s, a) => s + a.amountDelta));

  Widget _summaryCard(Invoice inv, SalesInvoiceFact? f, bool profit) {
    final cash = inv.paymentType == 'نقد';
    final paid = cash ? inv.totalAmount : (inv.amountPaidOnInvoice > inv.totalAmount ? inv.totalAmount : inv.amountPaidOnInvoice);
    final gross = f?.gross ?? 0;
    return SetCard(
      title: 'الملخص',
      icon: Icons.calculate_rounded,
      color: kSetGreen,
      child: Column(children: [
        const SizedBox(height: 6),
        if (f != null) ReportLine('مجموع البنود', gross, icon: Icons.list_alt_rounded),
        if (inv.discount > 0) ReportLine('الخصم', -inv.discount, icon: Icons.local_offer_rounded),
        if (inv.loadingFee > 0) ReportLine('أجور التحميل', inv.loadingFee, icon: Icons.local_shipping_rounded),
        if (_adjustments.isNotEmpty)
          ReportLine('التعديلات بعد الحفظ', _adjustments.fold<double>(0, (s, a) => s + a.amountDelta), icon: Icons.edit_note_rounded),
        if (f != null && _unexplained(inv, gross).abs() >= 1)
          ReportLine('فرق غير مفسَّر', _unexplained(inv, gross),
              icon: Icons.help_outline_rounded,
              color: kSetRed,
              hint: 'البنود لا تساوي مجموع الفاتورة (تعديل قديم على البنود؟)'),
        const Divider(height: 18),
        ReportLine('مجموع الفاتورة', inv.totalAmount, bold: true),
        if (inv.returnAmount > 0) ReportLine('الراجع', -inv.returnAmount, icon: Icons.keyboard_return_rounded),
        ReportLine('المدفوع', paid, icon: Icons.payments_rounded, color: kRepTeal),
        if (!cash)
          ReportLine('المتبقي على الحساب', inv.totalAmount - paid,
              icon: Icons.schedule_rounded, color: inv.totalAmount - paid > 0 ? kSetOrange : kSetGreen),
        if (profit && f != null) ...[
          const Divider(height: 18),
          ReportLine('الكلفة', f.cost, icon: Icons.price_change_rounded, color: kRepAmber),
          ReportLine('الربح', f.profit,
              icon: Icons.trending_up_rounded,
              color: kSetGreen,
              bold: true,
              hint: f.netSales.abs() > 0 ? 'هامش ${repPercent(f.profit / f.netSales * 100)}' : null),
        ],
      ]),
    );
  }
}

/// خلية جدول: النص لبداية العمود، والأرقام في منتصفه — العنوان وقيمته على نفس المحور.
/// (كان MoneyLabel باتجاه LTR داخل Expanded فيلتصق بيسار العمود بينما العنوان يمينه.)
Widget _cell(Widget child, {int flex = 2, bool numeric = true}) => Expanded(
      flex: flex,
      child: Align(alignment: numeric ? Alignment.center : AlignmentDirectional.centerStart, child: child),
    );

class _ItemHeader extends StatelessWidget {
  const _ItemHeader({required this.showProfit});
  final bool showProfit;
  @override
  Widget build(BuildContext context) {
    const st = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: kSetMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kSetBorder))),
      child: Row(children: [
        const SizedBox(width: 26, child: Text('#', style: st)),
        _cell(const Text('المادة', style: st), flex: 4, numeric: false),
        _cell(const Text('الكمية', style: st)),
        _cell(const Text('السعر', style: st)),
        _cell(const Text('المجموع', style: st)),
        if (showProfit) _cell(const Text('الربح', style: st)),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.n, required this.it, required this.showProfit, required this.zebra});
  final int n;
  final SalesItemFact it;
  final bool showProfit;
  final bool zebra;
  @override
  Widget build(BuildContext context) {
    final converted = it.saleType != it.baseUnit && it.baseQty != it.soldQty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: zebra ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        SizedBox(width: 26, child: Text('$n', style: const TextStyle(color: kSetMuted))),
        _cell(
          Text(it.productName,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
          flex: 4,
          numeric: false,
        ),
        _cell(Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${repQty(it.soldQty)} ${it.saleType}', style: const TextStyle(fontSize: 13, color: kSetText)),
          if (converted)
            Text('= ${repQty(it.baseQty)} ${it.baseUnit}', style: const TextStyle(fontSize: 11, color: kSetMuted)),
        ])),
        _cell(MoneyLabel(it.unitPrice, bold: false, size: 13)),
        _cell(MoneyLabel(it.revenue, size: 13)),
        if (showProfit) _cell(MoneyLabel(it.profit, size: 13, color: kSetGreen)),
      ]),
    );
  }
}
