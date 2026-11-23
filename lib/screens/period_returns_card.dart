// lib/screens/period_returns_card.dart
//
// ↩️ «مرتجعات الفواتير» داخل التقارير الدورية (يوم/شهر/سنة/من–إلى) — بطاقة ظاهرة:
//   • مستندات مرتجع المبيعات (ومنها مرتجعات الضمان): عددها ومبلغها، وكم رُدّ نقداً وكم نزل من الديون.
//   • «الراجع» المسجّل على الفواتير نفسها.
//   • آخر المستندات — اضغط أيّها أو «كل المرتجعات» لتقرير المرتجعات المفصّل للفترة نفسها.
// للقراءة فقط: من وقائع الفترة نفسها التي يحسب منها التقرير صافي المبيعات.

import 'package:flutter/material.dart';

import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'report_parts.dart' show openReport, repTime;
import 'returns_report_screen.dart';

class PeriodReturnsCard extends StatelessWidget {
  const PeriodReturnsCard({super.key, required this.from, required this.to, required this.facts});
  final DateTime from;
  final DateTime to;
  final SalesFacts facts;

  @override
  Widget build(BuildContext context) {
    final t = facts.totals();
    final docs = List.of(facts.returns)..sort((a, b) => b.date.compareTo(a.date));
    final onInv = facts.invoices.where((i) => i.returnAmount > 0).length;
    var cash = 0.0, credit = 0.0;
    for (final r in docs) {
      final c = r.refundMode == 'cash' ? r.total : (r.refundMode == 'mixed' ? r.cashPart : 0.0);
      cash += c;
      credit += r.total - c;
    }
    final warranty = docs.where((r) => (r.notes ?? '').startsWith('ضمان')).length;
    void open() => openReport(context, ReturnsReportScreen(from: from, to: to));

    return SetCard(
      title: 'مرتجعات الفواتير',
      subtitle: t.totalReturns <= 0
          ? 'لا مرتجعات في الفترة'
          : '${docs.length} مستند مرتجع${onInv > 0 ? ' • $onInv فاتورة فيها راجع' : ''}${warranty > 0 ? ' • $warranty من الضمان' : ''}',
      icon: Icons.assignment_return_rounded,
      color: kRepPurple,
      trailing: TextButton.icon(onPressed: open, icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('كل المرتجعات')),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KpiGrid(minTileWidth: 190, children: [
          KpiTile(
            label: 'إجمالي المرتجع',
            value: t.totalReturns,
            icon: Icons.keyboard_return_rounded,
            color: kRepPurple,
            emphasis: true,
            hint: t.sales > 0 ? '${repPercent(t.totalReturns / t.sales * 100)} من المبيعات' : null,
            onTap: open,
          ),
          KpiTile(
            label: 'مستندات المرتجع',
            value: t.salesReturns,
            icon: Icons.assignment_return_rounded,
            color: kSetBlue,
            hint: '${docs.length} مستند',
            onTap: open,
          ),
          KpiTile(label: 'رُدّ نقداً', value: cash, icon: Icons.point_of_sale_rounded, color: kSetRed, hint: 'خرج من الصناديق', onTap: open),
          KpiTile(label: 'نزل من الديون', value: credit, icon: Icons.account_balance_wallet_rounded, color: kSetOrange, onTap: open),
          if (t.invoiceReturns > 0)
            KpiTile(label: 'الراجع على الفواتير', value: t.invoiceReturns, icon: Icons.receipt_long_rounded, color: kSetMuted, hint: '$onInv فاتورة', onTap: open),
        ]),
        if (docs.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final r in docs.take(5))
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: kRepPurple.withValues(alpha: 0.12),
                    child: Icon((r.notes ?? '').startsWith('ضمان') ? Icons.verified_user_rounded : Icons.keyboard_return_rounded,
                        size: 16, color: kRepPurple),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r.number} — ${r.customerName}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${repDate(r.date)} ${repTime(r.date)} • ${r.refundModeArabic}',
                          style: const TextStyle(fontSize: 12, color: kSetMuted)),
                    ]),
                  ),
                  MoneyLabel(r.total),
                ]),
              ),
            ),
          if (docs.length > 5)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(onPressed: open, child: Text('و${docs.length - 5} مستند آخر — عرض الكل')),
            ),
        ],
      ]),
    );
  }
}
