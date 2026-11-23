// lib/erp/sales/invoice_returns_card.dart
//
// ↩️ ما رجع من الفاتورة — يظهر على الفاتورة نفسها (عرضها وتعديلها):
//   الفاتورة تبقى كما صدرت (المعيار المحاسبي)، وتحتها المرتجعات المربوطة بها: رقمها، تاريخها،
//   المواد وكمياتها، وكم رُدّ نقداً وكم نزل من الدين، وصافي الفاتورة بعدها، مع طباعة سند المرتجع.
// قراءة فقط.

import 'package:flutter/material.dart';

import '../../widgets/report_kit.dart';
import '../erp_common.dart' show erpDb;
import 'invoice_returns.dart';
import 'sales_return_screen.dart' show printSalesReturn;

String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

Future<List<InvoiceReturnDoc>> _load(int invoiceId) async {
  try {
    return await InvoiceReturns.forInvoice(await erpDb(), invoiceId);
  } catch (_) {
    return const [];
  }
}

/// بطاقة كاملة (شاشة تفاصيل الفاتورة). لا تظهر إن لم يكن عليها مرتجع.
class InvoiceReturnsCard extends StatefulWidget {
  const InvoiceReturnsCard({super.key, required this.invoiceId, this.invoiceTotal});
  final int invoiceId;
  final double? invoiceTotal;

  @override
  State<InvoiceReturnsCard> createState() => _InvoiceReturnsCardState();
}

class _InvoiceReturnsCardState extends State<InvoiceReturnsCard> {
  late final Future<List<InvoiceReturnDoc>> _f = _load(widget.invoiceId);

  @override
  Widget build(BuildContext context) {
    final invoiceTotal = widget.invoiceTotal;
    return FutureBuilder<List<InvoiceReturnDoc>>(
      future: _f,
      builder: (context, snap) {
        final docs = snap.data ?? const <InvoiceReturnDoc>[];
        if (docs.isEmpty) return const SizedBox.shrink();
        final total = docs.fold<double>(0, (s, d) => s + d.total);
        return SetCard(
          title: 'ما رجع من هذه الفاتورة',
          subtitle: '${docs.length} مرتجع • ${repMoney(total)}'
              '${invoiceTotal == null ? '' : ' • صافي الفاتورة بعده ${repMoney(invoiceTotal - total)}'}',
          icon: Icons.assignment_return_rounded,
          color: kRepPurple,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _Note(),
            const SizedBox(height: 8),
            for (final d in docs) _DocTile(doc: d),
          ]),
        );
      },
    );
  }
}

/// شريط مضغوط أعلى شاشة الفاتورة (عرض/تعديل). لا يظهر إن لم يكن عليها مرتجع.
class InvoiceReturnsStrip extends StatefulWidget {
  const InvoiceReturnsStrip({super.key, required this.invoiceId});
  final int invoiceId;

  @override
  State<InvoiceReturnsStrip> createState() => _InvoiceReturnsStripState();
}

class _InvoiceReturnsStripState extends State<InvoiceReturnsStrip> {
  // مرة واحدة: شاشة الفاتورة تُعاد بناؤها مع كل حرف يُكتب
  late final Future<List<InvoiceReturnDoc>> _f = _load(widget.invoiceId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InvoiceReturnDoc>>(
      future: _f,
      builder: (context, snap) {
        final docs = snap.data ?? const <InvoiceReturnDoc>[];
        if (docs.isEmpty) return const SizedBox.shrink();
        final total = docs.fold<double>(0, (s, d) => s + d.total);
        final items = <String>[
          for (final d in docs)
            for (final l in d.lines) '${_q(l.qty)} ${l.saleType} «${l.name}»',
        ];
        return Container(
          margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [kRepPurple.withValues(alpha: 0.09), kRepPurple.withValues(alpha: 0.03)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kRepPurple.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.assignment_return_rounded, color: kRepPurple),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'على هذه الفاتورة مرتجع: ${docs.map((d) => 'رقم ${d.no}').join('، ')} — ${repMoney(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: kRepPurple),
                ),
                Text(
                  'رجع: ${items.join('، ')}. الفاتورة تبقى كما بيعت، والمرتجع مستند مستقل يُنقص صافيها والمخزون ودين العميل.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: kSetMuted, height: 1.4),
                ),
              ]),
            ),
            TextButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (ctx) => SafeArea(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        const Text('ما رجع من هذه الفاتورة',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kSetText)),
                        const SizedBox(height: 8),
                        const _Note(),
                        const SizedBox(height: 8),
                        for (final d in docs) _DocTile(doc: d),
                      ],
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.visibility_rounded, size: 18),
              label: const Text('التفاصيل'),
            ),
          ]),
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note();
  @override
  Widget build(BuildContext context) => const Text(
        'كما في أنظمة ERP: الفاتورة لا تُعدَّل بعد المرتجع — المرتجع إشعار دائن مستقل مربوط بها. '
        'لإلغائه: المبيعات ← سجل المرتجعات.',
        style: TextStyle(fontSize: 12, color: kSetMuted, height: 1.5),
      );
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc});
  final InvoiceReturnDoc doc;

  @override
  Widget build(BuildContext context) {
    final d = doc;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kSetBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: kRepPurple.withValues(alpha: 0.12),
            child: Icon(d.warranty ? Icons.verified_user_rounded : Icons.keyboard_return_rounded, size: 17, color: kRepPurple),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مرتجع مبيعات رقم ${d.no}${d.warranty ? ' — ضمان' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: kSetText)),
              Text(
                [
                  if (d.date != null) repDate(d.date!),
                  d.modeArabic,
                  if (d.refundMode == 'mixed') 'نقداً ${repMoney(d.cash)} • من الدين ${repMoney(d.credit)}',
                ].join(' • '),
                style: const TextStyle(fontSize: 12, color: kSetMuted),
              ),
            ]),
          ),
          MoneyLabel(d.total),
        ]),
        const SizedBox(height: 6),
        for (final l in d.lines)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 42, top: 2),
            child: Row(children: [
              Expanded(child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${_q(l.qty)} ${l.saleType}', style: const TextStyle(color: kSetMuted)),
              const SizedBox(width: 12),
              MoneyLabel(l.total, size: 13),
            ]),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => printSalesReturn(context, d.id),
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('طباعة سند المرتجع'),
          ),
        ),
      ]),
    );
  }
}
