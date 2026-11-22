// lib/screens/period_vouchers_card.dart
//
// 🧾 «السندات في الفترة» داخل التقارير الدورية (يوم/شهر/سنة/من–إلى):
//   • ما خرج من الصناديق بالسندات: مصاريف (تنقص الربح)، مسحوبات المالك (حقوق ملكية،
//     لا تنقص الربح)، وصرف آخر — وما دخل بالسندات.
//   • أكبر الحسابات (كهرباء، رواتب، إيجار، مسحوبات…) — اضغط أيّها لكل سنداته.
//   • «الربح بعد مصاريف السندات» = ربح المبيعات − سندات المصروف (المسحوبات لا تُطرح).
//     الصافي الكامل (تالف، فروقات جرد، استهلاك…) في «قائمة الدخل».
// للقراءة فقط: نفس جدول السندات (غير المحذوفة) الذي تعرضه شاشة «السندات».

import 'package:flutter/material.dart';

import '../accounting/ledger.dart' show roundMoney;
import '../accounting/screens/acc_ui.dart' show accRoute;
import '../erp/erp_common.dart' show erpDb, d0, isoDay, isoDayAfter;
import '../erp/reports/vouchers_summary_report.dart';
import '../widgets/report_kit.dart';

class PeriodVouchersCard extends StatefulWidget {
  const PeriodVouchersCard({super.key, required this.from, required this.to, this.salesProfit});
  final DateTime from;
  final DateTime to;

  /// ربح المبيعات في الفترة (null = لا صلاحية لرؤية الربح).
  final double? salesProfit;

  @override
  State<PeriodVouchersCard> createState() => _PeriodVouchersCardState();
}

class _Acc {
  _Acc(this.name, this.kind);
  final String name;
  final String kind; // expense | drawings | payment
  double total = 0;
  int count = 0;
}

class _PeriodVouchersCardState extends State<PeriodVouchersCard> {
  bool _loading = true;
  String? _error;
  double _expense = 0, _drawings = 0, _payment = 0, _in = 0;
  int _countOut = 0;
  List<_Acc> _top = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PeriodVouchersCard old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await erpDb();
      final rows = await db.rawQuery('''
        SELECT v.voucher_type AS t, v.amount, a.name AS acc, a.system_key AS k
        FROM vouchers v LEFT JOIN accounts a ON a.id = v.account_id
        WHERE v.is_deleted = 0 AND v.voucher_type IN ('expense', 'payment', 'income', 'receipt')
          AND v.voucher_date >= ? AND v.voucher_date < ?''', [isoDay(widget.from), isoDayAfter(widget.to)]);
      var e = 0.0, dr = 0.0, p = 0.0, inn = 0.0;
      var n = 0;
      final accs = <String, _Acc>{};
      for (final r in rows) {
        final amt = d0(r['amount']);
        final t = '${r['t']}';
        if (t == 'income' || t == 'receipt') {
          inn += amt;
          continue;
        }
        n++;
        final kind = t == 'expense' ? 'expense' : (r['k'] == 'owner_drawings' ? 'drawings' : 'payment');
        switch (kind) {
          case 'expense':
            e += amt;
          case 'drawings':
            dr += amt;
          default:
            p += amt;
        }
        final name = '${r['acc'] ?? 'بلا حساب'}';
        final a = accs.putIfAbsent('$kind|$name', () => _Acc(name, kind));
        a.total = roundMoney(a.total + amt);
        a.count++;
      }
      final top = accs.values.toList()..sort((a, b) => b.total.compareTo(a.total));
      if (!mounted) return;
      setState(() {
        _expense = roundMoney(e);
        _drawings = roundMoney(dr);
        _payment = roundMoney(p);
        _in = roundMoney(inn);
        _countOut = n;
        _top = top.take(8).toList();
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = '$err';
        _loading = false;
      });
    }
  }

  void _openAll() => Navigator.push(context, accRoute(VouchersSummaryScreen(from: widget.from, to: widget.to)));

  @override
  Widget build(BuildContext context) {
    final out = roundMoney(_expense + _drawings + _payment);
    final profit = widget.salesProfit;
    return SetCard(
      title: 'السندات المسحوبة من الصناديق',
      subtitle: _loading ? 'جارٍ التحميل…' : '$_countOut سند خرج — اضغط أي رقم لكل سنداته وتفاصيلها',
      icon: Icons.receipt_long_rounded,
      color: kSetRed,
      trailing: TextButton.icon(onPressed: _openAll, icon: const Icon(Icons.open_in_new_rounded, size: 18), label: const Text('كل السندات')),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          : _error != null
              ? Text('تعذّر تحميل السندات: $_error', style: const TextStyle(color: kSetRed))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  KpiGrid(minTileWidth: 200, children: [
                    KpiTile(
                        label: 'إجمالي ما خرج',
                        value: out,
                        icon: Icons.north_east_rounded,
                        color: kSetRed,
                        emphasis: true,
                        hint: 'مصاريف + مسحوبات + صرف',
                        onTap: _openAll),
                    KpiTile(
                        label: 'المصاريف',
                        value: _expense,
                        icon: Icons.bolt_rounded,
                        color: kSetOrange,
                        hint: 'كهرباء، رواتب، إيجار… تنقص الربح',
                        onTap: _openAll),
                    KpiTile(
                        label: 'مسحوبات المالك',
                        value: _drawings,
                        icon: Icons.person_rounded,
                        color: kSetNavy,
                        hint: 'حقوق ملكية — لا تنقص الربح',
                        onTap: _openAll),
                    if (_payment > 0)
                      KpiTile(label: 'صرف آخر', value: _payment, icon: Icons.outbox_rounded, color: kSetMuted, onTap: _openAll),
                    KpiTile(label: 'دخل بالسندات', value: _in, icon: Icons.south_west_rounded, color: kSetGreen, hint: 'إيراد + قبض', onTap: _openAll),
                    if (profit != null)
                      KpiTile(
                        label: 'الربح بعد مصاريف السندات',
                        value: roundMoney(profit - _expense),
                        icon: Icons.account_balance_rounded,
                        color: profit - _expense >= 0 ? kSetGreen : kSetRed,
                        emphasis: true,
                        hint: 'ربح المبيعات − المصاريف (الصافي الكامل في قائمة الدخل)',
                      ),
                  ]),
                  if (_top.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final a in _top) _accRow(a, out),
                  ],
                ]),
    );
  }

  Widget _accRow(_Acc a, double out) {
    final pct = out <= 0 ? 0.0 : (a.total / out).clamp(0.0, 1.0).toDouble();
    final c = switch (a.kind) { 'expense' => kSetOrange, 'drawings' => kSetNavy, _ => kSetMuted };
    final tag = switch (a.kind) { 'expense' => 'مصروف', 'drawings' => 'مسحوبات', _ => 'صرف' };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(tag, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('${a.count} سند', style: const TextStyle(color: kSetMuted, fontSize: 12)),
            const SizedBox(width: 10),
            Text(repMoney(a.total), style: TextStyle(fontWeight: FontWeight.w800, color: c)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: pct, minHeight: 5, color: c, backgroundColor: c.withValues(alpha: 0.08)),
          ),
        ]),
      ),
    );
  }
}
