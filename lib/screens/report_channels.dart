// lib/screens/report_channels.dart
//
// 🧾 المبيعات حسب نوع البيع، ومرتجعات المبيعات منفصلة — بمصطلحات البرامج المحاسبية:
//   • «فواتير المبيعات»: فواتير «إنشاء فاتورة» (مفرد وجملة، نقداً أو آجلاً).
//   • «مبيعات نقاط البيع (الكاشير)»: إيصالات شاشة الكاشير.
//   • «مرتجعات المبيعات»: مستندات المرتجع، مفصولة حسب أصلها (فاتورة أو إيصال
//     كاشير) وطريقة الرد (نقداً أو من حساب العميل)، ومعها «الراجع المسجّل على
//     الفواتير» (تخفيض الفاتورة بعد حفظها).
//
// كل الأرقام من المحرك الموحّد (SalesFacts) فتطابق بقية التقارير.
// علامة «إيصال كاشير» في جدول invoice_tags منذ تحديث 20/10/2026؛ الإيصالات
// الأقدم منه تُحسب ضمن «فواتير المبيعات».

import 'package:flutter/material.dart';

import '../services/database_service.dart';
import '../services/invoice_upload_tracker.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';

class _Channel {
  int count = 0;
  double sales = 0, cash = 0, credit = 0, invoiceReturns = 0, profit = 0;
  void add(SalesInvoiceFact i) {
    count++;
    sales += i.total;
    if (i.isCash) {
      cash += i.total;
    } else {
      credit += i.total;
    }
    invoiceReturns += i.returnAmount;
    profit += i.profit;
  }
}

class SalesChannelsCard extends StatefulWidget {
  const SalesChannelsCard({
    super.key,
    required this.from,
    required this.to,
    required this.canProfit,
    this.facts,
    this.svc,
    this.onReturns,
  });

  final DateTime from;
  final DateTime to;
  final bool canProfit;

  /// وقائع الفترة إن كانت محمّلة؛ وإلا تُحمَّل هنا من [svc] (بفلتر مصدره)
  final SalesFacts? facts;
  final ReportsService? svc;
  final VoidCallback? onReturns;

  @override
  State<SalesChannelsCard> createState() => _SalesChannelsCardState();
}

class _SalesChannelsCardState extends State<SalesChannelsCard> {
  SalesFacts? _facts;
  Set<int> _pos = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SalesChannelsCard old) {
    super.didUpdateWidget(old);
    if (old.facts != widget.facts || old.from != widget.from || old.to != widget.to) _load();
  }

  Future<void> _load() async {
    try {
      final facts = widget.facts ?? await (widget.svc ?? ReportsService()).loadFacts(from: widget.from, to: widget.to);
      final db = await DatabaseService().database;
      await InvoiceUploadTracker.ensure(db);
      final rows = await db.rawQuery("SELECT invoice_id FROM invoice_tags WHERE source = 'pos'");
      if (!mounted) return;
      setState(() {
        _facts = facts;
        _pos = {for (final r in rows) (r['invoice_id'] as num).toInt()};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
    }
    final f = _facts;
    if (f == null) return const SizedBox.shrink();

    final regular = _Channel(), pos = _Channel();
    for (final i in f.invoices) {
      (_pos.contains(i.id) ? pos : regular).add(i);
    }
    final total = regular.sales + pos.sales;

    // مرتجعات المبيعات (المستندات) حسب الأصل وطريقة الرد
    var retCount = 0, retPosCount = 0;
    double ret = 0, retFromPos = 0, retCash = 0, retCredit = 0, retCost = 0;
    for (final r in f.returns) {
      retCount++;
      ret += r.total;
      retCost += r.cost;
      if (r.originalInvoiceId != null && _pos.contains(r.originalInvoiceId)) {
        retFromPos += r.total;
        retPosCount++;
      }
      final cashPart = r.refundMode == 'cash' ? r.total : (r.refundMode == 'mixed' ? r.cashPart : 0.0);
      retCash += cashPart;
      retCredit += r.total - cashPart;
    }
    final invRet = regular.invoiceReturns + pos.invoiceReturns;
    final allReturns = ret + invRet;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SetCard(
        title: 'المبيعات حسب نوع البيع',
        subtitle: 'فواتير المبيعات (إنشاء فاتورة) ومبيعات نقاط البيع (الكاشير) — قبل المرتجعات',
        icon: Icons.call_split_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          if (total > 0) _shareBar(regular.sales / total),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final a = _panel('فواتير المبيعات', 'مفرد وجملة من «إنشاء فاتورة»', Icons.receipt_long_rounded, kSetNavy, regular, total);
            final b = _panel('مبيعات نقاط البيع', 'إيصالات الكاشير', Icons.point_of_sale_rounded, kSetOrange, pos, total);
            if (c.maxWidth < 640) return Column(children: [a, const SizedBox(height: 10), b]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ]);
          }),
          const SizedBox(height: 8),
          const Text('إيصالات الكاشير قبل تحديث 20/10/2026 تُحسب ضمن فواتير المبيعات (لم تكن تُعلَّم).',
              style: TextStyle(fontSize: 11.5, color: kSetMuted)),
        ]),
      ),
      const SizedBox(height: 14),
      SetCard(
        title: 'مرتجعات المبيعات',
        subtitle: 'ما رجع من المبيعات في الفترة — منفصل عن المبيعات',
        icon: Icons.assignment_return_rounded,
        color: kSetRed,
        trailing: widget.onReturns == null
            ? null
            : TextButton.icon(
                onPressed: widget.onReturns,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('التفاصيل'),
              ),
        child: allReturns <= 0
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا مرتجعات في هذه الفترة', style: TextStyle(color: kSetMuted)),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 6),
                ReportLine('مستندات مرتجع المبيعات', ret,
                    icon: Icons.description_rounded, color: kSetRed, hint: '$retCount مستند'),
                if (ret > 0) ...[
                  ReportLine('  من فواتير المبيعات', ret - retFromPos, hint: '${retCount - retPosCount} مستند'),
                  ReportLine('  من إيصالات الكاشير', retFromPos, hint: '$retPosCount مستند'),
                  ReportLine('  رُدّ نقداً', retCash, icon: Icons.payments_outlined),
                  ReportLine('  خُصم من حساب العميل', retCredit, icon: Icons.person_outline_rounded),
                ],
                ReportLine('الراجع المسجّل على الفواتير', invRet,
                    icon: Icons.edit_note_rounded, color: kSetRed, hint: 'تخفيض الفاتورة بعد حفظها'),
                const Divider(height: 18),
                ReportLine('مجموع المرتجعات', allReturns, bold: true, color: kSetRed),
                ReportLine('صافي المبيعات بعد المرتجعات', total - allReturns, bold: true),
                if (widget.canProfit && ret > 0)
                  ReportLine('أثر المستندات على الربح', -(ret - retCost),
                      hint: 'مبلغ المرتجع ناقص كلفة البضاعة الراجعة للمخزن', color: kSetMuted),
                if (total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('نسبة المرتجعات: ${repPercent(allReturns / total * 100)} من المبيعات',
                        style: const TextStyle(fontSize: 12, color: kSetMuted)),
                  ),
              ]),
      ),
      const SizedBox(height: 14),
    ]);
  }

  Widget _shareBar(double regularShare) {
    final r = regularShare.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 12,
        child: Row(children: [
          if (r > 0) Expanded(flex: (r * 1000).round().clamp(1, 1000), child: Container(color: kSetNavy)),
          if (r < 1) Expanded(flex: ((1 - r) * 1000).round().clamp(1, 1000), child: Container(color: kSetOrange)),
        ]),
      ),
    );
  }

  Widget _panel(String title, String sub, IconData icon, Color color, _Channel c, double total) {
    final share = total > 0 ? c.sales / total * 100 : 0.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
              Text(sub, style: const TextStyle(fontSize: 11.5, color: kSetMuted)),
            ]),
          ),
          Text(repPercent(share), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
        const SizedBox(height: 8),
        ReportLine('المبيعات', c.sales, bold: true, hint: '${c.count} ${c.count == 1 ? 'فاتورة' : 'فاتورة/إيصال'}'),
        ReportLine('نقداً', c.cash, icon: Icons.payments_rounded, color: kRepTeal),
        ReportLine('آجل (دين)', c.credit, icon: Icons.schedule_rounded, color: kSetOrange),
        if (c.count > 0) ReportLine('متوسط الفاتورة', c.sales / c.count),
        if (widget.canProfit) ReportLine('الربح', c.profit, icon: Icons.trending_up_rounded, color: kSetGreen),
      ]),
    );
  }
}
